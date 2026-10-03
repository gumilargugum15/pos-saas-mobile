/// An outlet (`BranchResource`).
class Branch {
  const Branch({required this.id, required this.name, this.code, this.address, this.phone});

  final int id;
  final String name;
  final String? code;
  final String? address;
  final String? phone;

  @override
  bool operator ==(Object other) => other is Branch && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A customer (`CustomerResource`). Walk-in is not a customer row: it is
/// a sale with `customer_id = null`.
class Customer {
  const Customer({required this.id, required this.name, this.phone, this.email, this.address});

  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;

  @override
  bool operator ==(Object other) => other is Customer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
