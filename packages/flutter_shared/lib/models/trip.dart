class TripModel {
  final String id;
  final String status;
  final String city;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String? pickupAddress;
  final String? dropoffAddress;
  final double? estimatedFare;
  final double? finalFare;
  final String? captainId;
  final double? captainLat;
  final double? captainLng;
  final String currency;

  TripModel({
    required this.id,
    required this.status,
    required this.city,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    this.pickupAddress,
    this.dropoffAddress,
    this.estimatedFare,
    this.finalFare,
    this.captainId,
    this.captainLat,
    this.captainLng,
    this.currency = 'EGP',
  });

  factory TripModel.fromJson(Map<String, dynamic> json) => TripModel(
        id: json['id'] as String,
        status: json['status'] as String,
        city: json['city'] as String? ?? 'cairo',
        pickupLat: (json['pickup_lat'] as num).toDouble(),
        pickupLng: (json['pickup_lng'] as num).toDouble(),
        dropoffLat: (json['dropoff_lat'] as num).toDouble(),
        dropoffLng: (json['dropoff_lng'] as num).toDouble(),
        pickupAddress: json['pickup_address'] as String?,
        dropoffAddress: json['dropoff_address'] as String?,
        estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
        finalFare: (json['final_fare'] as num?)?.toDouble(),
        captainId: json['captain_id'] as String?,
        captainLat: (json['captain_lat'] as num?)?.toDouble(),
        captainLng: (json['captain_lng'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'EGP',
      );
}
