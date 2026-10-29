import 'package:flutter/material.dart';

class CountryPickerDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  const CountryPickerDialog({super.key, required this.title, required this.items});

  @override
  State<CountryPickerDialog> createState() => _CountryPickerDialogState();
}

class _CountryPickerDialogState extends State<CountryPickerDialog> {
  late List<String> _filtered;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _search.addListener(() {
      setState(() {
        _filtered = widget.items
            .where((e) => e.toLowerCase().contains(_search.text.toLowerCase()))
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search...',
                filled: true,
                fillColor: const Color(0xFFE6E6E6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 400,
              width: double.maxFinite,
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(_filtered[i], style: const TextStyle(fontSize: 16)),
                  onTap: () => Navigator.pop(context, _filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
