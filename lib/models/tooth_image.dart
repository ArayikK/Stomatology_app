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

  /// Millimetres per pixel: read from the DICOM on import, or set by the
  /// dentist calibrating a photo against a known length. Null means lengths
  /// can only be shown in pixels.
  final double? pixelSpacingMm;

  /// Brightness/contrast/inversion chosen for this image - see
  /// lib/models/image_view_settings.dart.
  final String? viewSettingsJson;

  /// For a CBCT series: the folder holding every rendered slice, and how
  /// many there are. [filePath] is the slice shown first.
  final String? seriesDir;
  final int? sliceCount;

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
    this.pixelSpacingMm,
    this.viewSettingsJson,
    this.seriesDir,
    this.sliceCount,
    required this.createdAt,
  });

  bool get isPaired => pairedImageId != null;
  bool get isCalibrated => pixelSpacingMm != null && pixelSpacingMm! > 0;
  bool get isSeries => (sliceCount ?? 0) > 1 && seriesDir != null;
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
      'pixel_spacing_mm': pixelSpacingMm,
      'view_settings_json': viewSettingsJson,
      'series_dir': seriesDir,
      'slice_count': sliceCount,
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
      pixelSpacingMm: (map['pixel_spacing_mm'] as num?)?.toDouble(),
      viewSettingsJson: map['view_settings_json'] as String?,
      seriesDir: map['series_dir'] as String?,
      sliceCount: (map['slice_count'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
