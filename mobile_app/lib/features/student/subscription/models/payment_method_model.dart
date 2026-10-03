/// A payment method of a transportation company (company_payment_methods).
/// Students only receive active methods of companies they can subscribe to.
class PaymentMethodModel {
  final String id;
  final String type; // instapay | vodafone_cash | bank
  final String displayName;
  final String? accountHolder;
  final String? instapayAddress;
  final String? walletPhone;
  final String? bankName;
  final String? bankAccountNumber;
  final String? iban;
  final String? instructions;

  const PaymentMethodModel({
    required this.id,
    required this.type,
    required this.displayName,
    this.accountHolder,
    this.instapayAddress,
    this.walletPhone,
    this.bankName,
    this.bankAccountNumber,
    this.iban,
    this.instructions,
  });

  String get typeLabel => switch (type) {
        'instapay' => 'InstaPay',
        'vodafone_cash' => 'Vodafone Cash',
        _ => 'تحويل بنكي',
      };

  /// The value the student copies to pay (address, wallet number or account).
  String get payTo => switch (type) {
        'instapay' => instapayAddress ?? '',
        'vodafone_cash' => walletPhone ?? '',
        _ => bankAccountNumber ?? '',
      };

  factory PaymentMethodModel.fromJson(Map<String, dynamic> json) => PaymentMethodModel(
        id: json['id'] as String,
        type: json['method_type'] as String? ?? 'bank',
        displayName: json['display_name'] as String? ?? '',
        accountHolder: json['account_holder'] as String?,
        instapayAddress: json['instapay_address'] as String?,
        walletPhone: json['wallet_phone'] as String?,
        bankName: json['bank_name'] as String?,
        bankAccountNumber: json['bank_account_number'] as String?,
        iban: json['iban'] as String?,
        instructions: json['instructions'] as String?,
      );
}
