enum UserRole {
  student,
  supervisor,
  admin,
  unknown;

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'student':
        return UserRole.student;
      case 'supervisor':
        return UserRole.supervisor;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.unknown;
    }
  }
}
