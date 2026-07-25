class RideRequestModel {
  final String id;
  final String riderId;
  final String riderName;
  final String riderPhone;
  final String riderAvatar;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;
  final double distanceKm;
  final double offeredPrice;
  final double captainToPickupKm;
  final String createdAt;
  final String city;

  RideRequestModel({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.riderPhone,
    required this.riderAvatar,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.offeredPrice,
    required this.captainToPickupKm,
    required this.createdAt,
    required this.city,
  });

  factory RideRequestModel.fromJson(Map<String, dynamic> json) {
    return RideRequestModel(
      id: json['id'] as String,
      riderId: json['rider_id'] as String? ?? '',
      riderName: json['rider_name'] as String? ?? 'عميل GoDrive',
      riderPhone: json['rider_phone'] as String? ?? '',
      riderAvatar: json['rider_avatar'] as String? ?? '',
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      pickupAddress: json['pickup_address'] as String? ?? 'موقع الانطلاق',
      dropoffLat: (json['dropoff_lat'] as num).toDouble(),
      dropoffLng: (json['dropoff_lng'] as num).toDouble(),
      dropoffAddress: json['dropoff_address'] as String? ?? 'موقع الوصول',
      distanceKm: (json['distance_km'] as num? ?? 5.0).toDouble(),
      offeredPrice: (json['offered_price'] as num? ?? 25.0).toDouble(),
      captainToPickupKm: (json['captain_to_pickup_km'] as num? ?? 1.0).toDouble(),
      createdAt: json['created_at'] as String? ?? '',
      city: json['city'] as String? ?? 'cairo',
    );
  }
}
