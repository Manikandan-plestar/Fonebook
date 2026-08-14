import 'package:flutter/material.dart';

class InputField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  const InputField({super.key, required this.hint, required this.controller, this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF717171)),
          fillColor: const Color(0xFFE6E6E6),
          filled: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
        ),
        style: const TextStyle(color: Color(0xFF272000), fontSize: 16),
      ),
    );
  }
}

class ClickableField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final VoidCallback onTap;
  const ClickableField({super.key, required this.hint, required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(color: const Color(0xFFE6E6E6), borderRadius: BorderRadius.circular(4)),
          alignment: Alignment.centerLeft,
          child: Text(
            controller.text.isEmpty ? hint : controller.text,
            style: TextStyle(
              color: controller.text.isEmpty ? const Color(0xFF717171) : const Color(0xFF272000),
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class SearchDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  final Function(String) onSelected;
  const SearchDialog({super.key, required this.title, required this.items, required this.onSelected});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late List<String> _filtered;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(hintText: 'Search...', border: OutlineInputBorder()),
                onChanged: (v) {
                  setState(() {
                    _filtered = widget.items.where((e) => e.toLowerCase().contains(v.toLowerCase())).toList();
                  });
                },
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.title == 'Select City' ? 'Please select a state first' : 'No items found',
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(_filtered[i]),
                        onTap: () {
                          widget.onSelected(_filtered[i]);
                          Navigator.pop(context);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
