class ToothImage {
  final int? id;
  final int patientId;
  final int toothNumber;
  final String filePath;

  /// Present when this image was imported from a DICOM (.dcm) file - the
  /// original file, preserved alongside the flattened PNG/JPEG at
  /// [filePath] that the app actually displays.
  final String? originalDicomPath;
  final DateTime createdAt;

  const ToothImage({
    this.id,
    required this.patientId,
    required this.toothNumber,
    required this.filePath,
    this.originalDicomPath,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'tooth_number': toothNumber,
      'file_path': filePath,
      'original_dicom_path': originalDicomPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ToothImage.fromMap(Map<String, Object?> map) {
    return ToothImage(
      id: map['id'] as int?,
      patientId: map['patient_id'] as int,
      toothNumber: map['tooth_number'] as int,
      filePath: map['file_path'] as String,
      originalDicomPath: map['original_dicom_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
