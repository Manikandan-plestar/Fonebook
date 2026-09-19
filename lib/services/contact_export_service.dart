import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart' hide PermissionStatus;

import 'api_client.dart';
import '../utils/string_utils.dart';

/// Progress states for the export workflow.
enum ExportStep {
  preparing,
  exporting,
  error,
}

/// Service to handle batch exporting of contacts to the device address book.
/// Provides immediate UI feedback by displaying a progress dialog before any heavy
/// asynchronous preparation (permission check, network fetch, device contact queries) begins.
class ContactExportService {
  /// Entry point to trigger the contact export flow.
  ///
  /// Either [preSelectedContacts] or [selectedPhones] should be provided.
  /// [fallbackContacts] can be supplied if authoritative database query is offline.
  static Future<void> startExport({
    required BuildContext context,
    required ApiClient api,
    required String email,
    List<Map<String, dynamic>>? preSelectedContacts,
    Set<String>? selectedPhones,
    List<Map<String, dynamic>>? fallbackContacts,
    VoidCallback? onComplete,
  }) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _ExportProgressDialog(
        api: api,
        email: email,
        preSelectedContacts: preSelectedContacts,
        selectedPhones: selectedPhones,
        fallbackContacts: fallbackContacts,
        onComplete: onComplete,
      ),
    );
  }
}

class _ExportProgressDialog extends StatefulWidget {
  final ApiClient api;
  final String email;
  final List<Map<String, dynamic>>? preSelectedContacts;
  final Set<String>? selectedPhones;
  final List<Map<String, dynamic>>? fallbackContacts;
  final VoidCallback? onComplete;

  const _ExportProgressDialog({
    required this.api,
    required this.email,
    this.preSelectedContacts,
    this.selectedPhones,
    this.fallbackContacts,
    this.onComplete,
  });

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  ExportStep _step = ExportStep.preparing;
  int _current = 0;
  int _total = 0;
  String _errorTitle = '';
  String _errorMessage = '';
  bool _isPermissionError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runExportPipeline();
    });
  }

  Future<void> _runExportPipeline() async {
    try {
      // 1. Request Contacts Permission asynchronously
      bool hasPermission = false;
      try {
        final status = await Permission.contacts.request();
        hasPermission = status.isGranted || await Permission.contacts.isGranted;
      } catch (e) {
        debugPrint('[EXPORT] Error requesting Permission.contacts: $e');
      }

      if (!hasPermission) {
        try {
          hasPermission =
              await FlutterContacts.permissions.request(PermissionType.read) ==
                  PermissionStatus.granted;
        } catch (e) {
          debugPrint('[EXPORT] Error requesting FlutterContacts permission: $e');
        }
      }

      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _step = ExportStep.error;
          _isPermissionError = true;
          _errorTitle = 'Permission Required';
          _errorMessage =
              'Contact permission is required to export contacts to your device.';
        });
        return;
      }

      // 2. Fetch authoritative contacts from DB or use pre-selected contacts
      List<Map<String, dynamic>> rawSourceContacts = [];
      if (widget.preSelectedContacts != null &&
          widget.preSelectedContacts!.isNotEmpty) {
        rawSourceContacts =
            List<Map<String, dynamic>>.from(widget.preSelectedContacts!);
      } else {
        List<Map<String, dynamic>> allDbContacts = [];
        try {
          final dbRes = await widget.api.post('get_my_contacts', {
            'email': widget.email,
            'owner_email': widget.email,
          });

          if (dbRes is List) {
            for (final item in dbRes) {
              if (item is Map) {
                allDbContacts.add(Map<String, dynamic>.from(item));
              }
            }
          } else if (dbRes is Map && dbRes['data'] is List) {
            for (final item in dbRes['data']) {
              if (item is Map) {
                allDbContacts.add(Map<String, dynamic>.from(item));
              }
            }
          } else if (dbRes is Map && dbRes['contacts'] is List) {
            for (final item in dbRes['contacts']) {
              if (item is Map) {
                allDbContacts.add(Map<String, dynamic>.from(item));
              }
            }
          }
        } catch (e) {
          debugPrint('[EXPORT] Error fetching authoritative contacts: $e');
        }

        final phoneSet = widget.selectedPhones ?? <String>{};
        final selectedDbContacts = allDbContacts.where((db) {
          final phone =
              db['phone']?.toString() ?? db['phone_no']?.toString() ?? '';
          return phoneSet.contains(phone);
        }).toList();

        if (selectedDbContacts.isNotEmpty) {
          rawSourceContacts = selectedDbContacts;
        } else if (widget.fallbackContacts != null &&
            widget.fallbackContacts!.isNotEmpty) {
          rawSourceContacts = widget.fallbackContacts!.where((item) {
            final phone =
                item['phone']?.toString() ?? item['phone_no']?.toString() ?? '';
            return phoneSet.contains(phone);
          }).toList();
        }
      }

      if (rawSourceContacts.isEmpty) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No contacts selected for export.'),
            backgroundColor: Colors.orange,
          ),
        );
        widget.onComplete?.call();
        return;
      }

      // 3. De-duplicate among selection using normalized phone numbers
      final seenSelectedKeys = <String>{};
      final uniqueSelectedContacts = <Map<String, dynamic>>[];

      for (final contact in rawSourceContacts) {
        final rawPhone =
            contact['phone']?.toString() ?? contact['phone_no']?.toString() ?? '';
        final key = getCanonicalPhoneKey(rawPhone);
        if (key.isNotEmpty) {
          if (seenSelectedKeys.contains(key)) {
            continue; // Duplicate within selection, keep only one
          }
          seenSelectedKeys.add(key);
        }
        uniqueSelectedContacts.add(contact);
      }

      // 4. Query existing device contacts asynchronously for duplicate detection
      final fastProperties = ContactProperty.values
          .where((p) => p.name != 'photo' && p.name != 'thumbnail')
          .toSet();
      List<Contact> deviceContacts = [];
      try {
        deviceContacts =
            await FlutterContacts.getAll(properties: fastProperties);
      } catch (e) {
        debugPrint('[EXPORT] Error reading device contacts: $e');
      }

      final existingDevicePhoneKeys = <String>{};
      for (final dc in deviceContacts) {
        for (final p in dc.phones) {
          final key = getCanonicalPhoneKey(p.number);
          if (key.isNotEmpty) {
            existingDevicePhoneKeys.add(key);
          }
        }
      }

      // 5. Separate new contacts from skipped duplicates
      final List<Map<String, dynamic>> toExportList = [];
      int skippedCount = 0;

      for (final contact in uniqueSelectedContacts) {
        final rawPhone =
            contact['phone']?.toString() ?? contact['phone_no']?.toString() ?? '';
        final key = getCanonicalPhoneKey(rawPhone);
        if (key.isNotEmpty && existingDevicePhoneKeys.contains(key)) {
          skippedCount++;
        } else {
          toExportList.add(contact);
        }
      }

      if (toExportList.isEmpty) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skippedCount == 1
                  ? 'The selected contact already exists on your device.'
                  : 'All $skippedCount selected contacts already exist on your device.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        widget.onComplete?.call();
        return;
      }

      // 6. Transition to Exporting state
      if (!mounted) return;
      setState(() {
        _step = ExportStep.exporting;
        _total = toExportList.length;
        _current = 0;
      });

      // 7. Perform the export loop
      int exportedCount = 0;
      int failedCount = 0;
      String? lastExportError;
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < toExportList.length; i++) {
        final contact = toExportList[i];
        final rawName = (contact['name']?.toString() ?? '').trim();
        final rawPhone =
            contact['phone']?.toString() ?? contact['phone_no']?.toString() ?? '';
        final cleanPhone = normalizePhoneNumber(rawPhone);
        final title = (contact['title']?.toString() ?? '').trim();
        final emailVal = (contact['email']?.toString() ?? '').trim();
        final additionalPhonesRaw = contact['phonenos']?.toString() ??
            contact['additional_phones']?.toString() ??
            '';

        // Construct Name parts
        final nameParts = rawName.split(' ');
        final firstName = nameParts.isNotEmpty
            ? nameParts.first
            : (rawName.isNotEmpty ? rawName : 'Contact');
        final lastName =
            nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        // Construct Phones list
        final phonesList = <Phone>[Phone(number: cleanPhone)];
        if (additionalPhonesRaw.isNotEmpty) {
          for (final p in additionalPhonesRaw.split(RegExp(r'[,;]'))) {
            final normalizedExtra = normalizePhoneNumber(p.trim());
            if (normalizedExtra.isNotEmpty && normalizedExtra != cleanPhone) {
              phonesList.add(Phone(number: normalizedExtra));
            }
          }
        }

        // Construct Emails list
        final emailsList = <Email>[];
        if (emailVal.isNotEmpty && emailVal.contains('@')) {
          emailsList.add(Email(address: emailVal));
        }

        // Construct Organizations list
        final orgList = <Organization>[];
        if (title.isNotEmpty) {
          orgList.add(Organization(name: title, jobTitle: title));
        }

        final newContact = Contact(
          name: Name(
            first: firstName,
            last: lastName,
          ),
          phones: phonesList,
          emails: emailsList,
          organizations: orgList,
        );

        try {
          await FlutterContacts.create(newContact);
          exportedCount++;
        } catch (e) {
          debugPrint('[EXPORT] Error exporting contact $rawName: $e');
          lastExportError = e.toString();
          failedCount++;
        }

        if (mounted) {
          setState(() {
            _current = exportedCount + failedCount;
          });
        }

        // Yield execution periodically to allow smooth rendering of the UI
        if ((exportedCount + failedCount) % 5 == 0 ||
            (exportedCount + failedCount) == toExportList.length) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 800) {
        await Future.delayed(Duration(milliseconds: 800 - elapsed));
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress dialog

      // 8. Show descriptive result SnackBar
      if (failedCount == 0) {
        if (skippedCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                exportedCount == 1
                    ? '1 contact exported successfully.'
                    : '$exportedCount contacts exported successfully.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$exportedCount contact${exportedCount > 1 ? 's' : ''} exported successfully. $skippedCount duplicate contact${skippedCount > 1 ? 's were' : ' was'} skipped.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (exportedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export completed: $exportedCount exported, $skippedCount skipped, $failedCount failed.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lastExportError != null &&
                      lastExportError.contains('permission')
                  ? 'Write contacts permission is required to save contacts.'
                  : 'Failed to export $failedCount contact(s). Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }

      widget.onComplete?.call();
    } catch (e) {
      debugPrint('[EXPORT] General export error: $e');
      if (!mounted) return;
      setState(() {
        _step = ExportStep.error;
        _isPermissionError = false;
        _errorTitle = 'Export Error';
        _errorMessage = 'An unexpected error occurred while exporting: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == ExportStep.error) {
      return AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorTitle,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_isPermissionError)
            TextButton(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
                openAppSettings();
              },
              child: const Text(
                'Settings',
                style: TextStyle(
                  color: Color(0xFF4C5B8F),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Colors.grey,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      );
    }

    if (_step == ExportStep.exporting) {
      return AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Exporting Contacts',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '$_current / $_total',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF4C5B8F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _total > 0 ? (_current / _total).clamp(0.0, 1.0) : null,
                  backgroundColor: const Color(0xFFEEEEEE),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFD7B41A)),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please wait while contacts are being exported.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default: ExportStep.preparing
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: const Padding(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFD7B41A),
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export Contacts',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Preparing contacts...',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
