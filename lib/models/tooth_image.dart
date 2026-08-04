enum ImageRole { before, after }

class ToothImage {
  final int? id;
  final int patientId;
  final int toothNumber;
  final String filePath;

  /// Present when this image was imported from a DICOM (.dcm) file - the
  /// original file, preserved alongside the flattened PNG/JPEG at
  /// [filePath] that the app actually displays.
  final String? originalDicomPath;

  /// Set on both sides of a before/after pair once paired via
  /// DentalRepository.pairImages.
  final ImageRole? role;
  final int? pairedImageId;

  /// Raw JSON of drawn annotations/measurements - see
  /// lib/models/annotation_shape.dart for the shape it decodes to.
  final String? annotationsJson;
  final DateTime createdAt;

  const ToothImage({
    this.id,
    required this.patientId,
    required this.toothNumber,
    required this.filePath,
    this.originalDicomPath,
    this.role,
    this.pairedImageId,
    this.annotationsJson,
    required this.createdAt,
  });

  bool get isPaired => pairedImageId != null;
  bool get hasAnnotations => (annotationsJson ?? '').trim().isNotEmpty && annotationsJson != '[]';

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'tooth_number': toothNumber,
      'file_path': filePath,
      'original_dicom_path': originalDicomPath,
      'role': role?.name,
      'paired_image_id': pairedImageId,
      'annotations_json': annotationsJson,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ToothImage.fromMap(Map<String, Object?> map) {
    final roleName = map['role'] as String?;
    return ToothImage(
      id: map['id'] as int?,
      patientId: map['patient_id'] as int,
      toothNumber: map['tooth_number'] as int,
      filePath: map['file_path'] as String,
      originalDicomPath: map['original_dicom_path'] as String?,
      role: roleName == null
          ? null
          : ImageRole.values.firstWhere((r) => r.name == roleName, orElse: () => ImageRole.before),
      pairedImageId: map['paired_image_id'] as int?,
      annotationsJson: map['annotations_json'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
