import 'package:flutter/material.dart';
import '../models/risk_result.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

class VerifyDataScreen extends StatefulWidget {
  final RiskResult initialResult;

  const VerifyDataScreen({super.key, required this.initialResult});

  @override
  State<VerifyDataScreen> createState() => _VerifyDataScreenState();
}

class _VerifyDataScreenState extends State<VerifyDataScreen> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> _features;
  bool _isRecalculating = false;
  String _selectedCategory = 'Personal';

  @override
  void initState() {
    super.initState();
    // Use a very safe way to copy the features map
    final sourceFeatures = widget.initialResult.features;
    _features = Map<String, dynamic>.from(sourceFeatures);
  }

  Future<void> _handleConfirm() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isRecalculating = true);
    try {
      final updatedResult = await ApiService.recalculate(
        _features,
        fileName: widget.initialResult.fileName,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(result: updatedResult),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isRecalculating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Verify Extracted Data'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── File Info Header ─────────────────────────────────
            _buildFileHeader(),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Financial Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Text(
                      'Review and correct extracted values',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildStyledField('Monthly Net Income', 'monthly_income', isCurrency: true),
                    _buildStyledField('Loan Amount Requested', 'loan_amount', isCurrency: true),
                    _buildStyledField('Existing Monthly EMI', 'existing_emis', isCurrency: true),
                    _buildStyledField('Employment Years', 'employment_years'),
                    _buildStyledField('CIBIL Score (300-900)', 'credit_score'),

                    const SizedBox(height: 24),
                    const Text(
                      'Loan Category',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryList(),

                    const SizedBox(height: 40),
                    _buildActionButtons(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description, color: Color(0xFFEF4444), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialResult.fileName ?? 'Unnamed Document',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 10, color: Color(0xFF059669)),
                      SizedBox(width: 4),
                      Text(
                        'Data Extracted',
                        style: TextStyle(
                          color: Color(0xFF059669),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledField(String label, String key, {bool isCurrency = false}) {
    dynamic rawValue = _features[key];
    String displayValue = rawValue?.toString() ?? '';
    
    // For currency fields, ensure we show a clean integer if it's a number
    if (isCurrency && rawValue != null) {
      double? numValue;
      if (rawValue is num) {
        numValue = rawValue.toDouble();
      } else if (rawValue is String) {
        numValue = double.tryParse(rawValue.replaceAll(RegExp(r'[^0-9.]'), ''));
      }
      
      if (numValue != null) {
        displayValue = '₹${numValue.toStringAsFixed(0)}';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF374151),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: displayValue,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            keyboardType: TextInputType.number,
            onSaved: (val) {
              String cleanVal = val ?? '0';
              if (isCurrency) {
                cleanVal = cleanVal.replaceAll('₹', '').replaceAll(',', '');
              }
              _features[key] = double.tryParse(cleanVal) ?? 0.0;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final categories = [
      'Personal',
      'Education',
      'Medical',
      'Home Improvement',
      'Debt Consolidation',
      'Venture',
    ];

    return Column(
      children: categories.map((cat) {
        final isSelected = _selectedCategory == cat;
        return InkWell(
          onTap: () => setState(() => _selectedCategory = cat),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE5E7EB) : Colors.transparent,
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: Text(
              cat,
              style: TextStyle(
                color: isSelected ? const Color(0xFF111827) : const Color(0xFF374151),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF111827))),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isRecalculating ? null : _handleConfirm,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isRecalculating
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Calculate Risk', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
