// Utility: Department & Batch scoping helpers
// All Firestore sub-collection paths for multi-dept architecture go through here.

/// Full list of all 11 BUTEX departments.
/// Each entry: { 'code': 'IPE', 'name': 'Industrial & Production Engineering' }
const List<Map<String, String>> kDepartments = [
  {'code': 'WPE', 'name': 'Wet Process Engineering'},
  {'code': 'AE', 'name': 'Apparel Engineering'},
  {'code': 'FE', 'name': 'Fabric Engineering'},
  {'code': 'DCE', 'name': 'Dyes and Chemical Engineering'},
  {'code': 'IPE', 'name': 'Industrial & Production Engineering'},
  {'code': 'YE', 'name': 'Yarn Engineering'},
  {'code': 'ESE', 'name': 'Environmental Science & Engineering'},
  {'code': 'TEM', 'name': 'Textile Engineering Management'},
  {'code': 'TMDM', 'name': 'Textile Machinery Design & Maintenance'},
  {'code': 'TME', 'name': 'Textile Materials Engineering'},
  {'code': 'TFD', 'name': 'Textile Fashion & Design'},
];

/// Dept codes only (for dropdowns / validation).
final List<String> kDeptCodes = kDepartments.map((d) => d['code']!).toList();

/// Get the full name for a dept code, or return the code itself if not found.
String deptFullName(String code) {
  final match = kDepartments.firstWhere(
    (d) => d['code'] == code,
    orElse: () => {'code': code, 'name': code},
  );
  return match['name']!;
}

/// Supported batch numbers.
const List<String> kBatches = ['48', '49', '50', '51', '52'];

/// Build the Firestore sub-collection path for a given dept, batch, and collection name.
/// e.g. deptBatchCol('IPE', '51', 'announcements')
///      → 'depts/IPE/batches/51/announcements'
String deptBatchCol(String dept, String batch, String collection) {
  return 'depts/$dept/batches/$batch/$collection';
}

/// Returns true if the user has a valid (non-empty) department and batch.
bool userScopeIsValid(String? department, String? batch) {
  return department != null &&
      department.isNotEmpty &&
      batch != null &&
      batch.isNotEmpty;
}
