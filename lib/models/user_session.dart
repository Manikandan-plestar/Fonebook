class UserSession {
  final String? phone;
  final String? email;
  final String? place;
  final String? place1;
  final String? country;
  final String? image;
  final bool premium;

  const UserSession({this.phone, this.email, this.place, this.place1, this.country, this.image, this.premium = false});
}
