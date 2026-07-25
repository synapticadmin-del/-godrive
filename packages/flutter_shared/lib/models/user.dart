class UserModel {
  final String id;
  final String email;
  final String? name;
  final String role;
  final String status;

  UserModel({
    required this.id,
    required this.email,
    this.name,
    required this.role,
    required this.status,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String?,
        role: json['role'] as String,
        status: json['status'] as String? ?? 'active',
      );
}
