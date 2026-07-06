import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String email;
  final bool isCR;
  final bool isAdmin;
  final bool isApproved;
  final String name;
  final String studentId;
  final String batch;
  final String department; // e.g. 'IPE', 'WPE', 'AE'
  final String phoneNumber;
  final String photoUrl;
  final String schoolName;
  final String collegeName;

  AppUser({
    required this.id,
    required this.email,
    this.isCR = false,
    this.isAdmin = false,
    this.isApproved = false,
    this.name = '',
    this.studentId = '',
    this.batch = '',
    this.department = '',
    this.phoneNumber = '',
    this.photoUrl = '',
    this.schoolName = '',
    this.collegeName = '',
  });

  /// Firestore sub-collection base path for this user's dept+batch.
  /// e.g. 'depts/IPE/batches/51'
  String get deptBatchPath => 'depts/$department/batches/$batch';

  /// Whether this user has a fully set department & batch.
  bool get hasDeptScope => department.isNotEmpty && batch.isNotEmpty;

  factory AppUser.fromMap(Map<String, dynamic> data, String documentId) {
    return AppUser(
      id: documentId,
      email: data['email'] ?? '',
      isCR: data['isCR'] ?? false,
      isAdmin: data['isAdmin'] ?? false,
      isApproved: data['isApproved'] ?? false,
      name: data['name'] ?? '',
      studentId: data['studentId'] ?? '',
      batch: data['batch'] ?? '',
      department: data['department'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      schoolName: data['schoolName'] ?? '',
      collegeName: data['collegeName'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'isCR': isCR,
      'isAdmin': isAdmin,
      'isApproved': isApproved,
      'name': name,
      'studentId': studentId,
      'batch': batch,
      'department': department,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
      'schoolName': schoolName,
      'collegeName': collegeName,
    };
  }
}

class Announcement {
  final String id;
  final String title;
  final String content;
  final String type; // 'Urgent', 'Notice', 'Material'
  final DateTime timestamp;
  final String postedBy;
  final String? fileUrl;
  final String? fileName;
  /// Optional structured detail line shown in the info-box on the card.
  /// Stored as a single string, e.g. "Room No: TA06" or "Venue: Main Auditorium"
  final String? details;

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.timestamp,
    required this.postedBy,
    this.fileUrl,
    this.fileName,
    this.details,
  });

  factory Announcement.fromMap(Map<String, dynamic> data, String id) {
    return Announcement(
      id: id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      type: data['type'] ?? 'Notice',
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      postedBy: data['postedBy'] ?? '',
      fileUrl: data['fileUrl'],
      fileName: data['fileName'],
      details: data['details'],
    );
  }
}

class ClassSchedule {
  final String id;
  final String dayOfWeek;
  final String subject;
  final String subname;
  final String room;
  final String time; // Can still be used for display, e.g. "8:00 - 9:40"
  final String status; // 'pending', 'upcoming', 'completed', 'cancelled'
  final int startSlot; // 1 to 10
  final int span; // 1, 2, or 3
  final String teacher;
  final String group; // e.g. 'Gr: A'
  final DateTime? lastUpdatedDate; // To handle auto-resetting status every week
  final DateTime? scheduledDate; // To support week-specific classes

  ClassSchedule({
    required this.id,
    required this.dayOfWeek,
    required this.subject,
    this.subname = '',
    required this.room,
    required this.time,
    this.status = 'upcoming',
    this.startSlot = 1,
    this.span = 1,
    this.teacher = '',
    this.group = '',
    this.lastUpdatedDate,
    this.scheduledDate,
  });

  factory ClassSchedule.fromMap(Map<String, dynamic> data, String id) {
    String parsedStatus = data['status'] ?? 'pending';
    if (data['isCancelled'] == true) {
      parsedStatus = 'cancelled';
    }

    final rawTime = data['time'] ?? '';
    int parsedStartSlot = data['startSlot'] ?? 0;
    int parsedSpan = data['span'] ?? 0;

    // Smart parsing for legacy database entries to distribute them horizontally
    if (data['startSlot'] == null ||
        data['span'] == null ||
        parsedStartSlot == 0) {
      final parsed = _parseTimeSlot(rawTime);
      parsedStartSlot = parsed['startSlot']!;
      parsedSpan = parsed['span']!;
    }

    return ClassSchedule(
      id: id,
      dayOfWeek: data['dayOfWeek'] ?? '',
      subject: data['subject'] ?? '',
      subname: data['subname'] ?? '',
      room: data['room'] ?? '',
      time: rawTime,
      status: parsedStatus,
      startSlot: parsedStartSlot,
      span: parsedSpan,
      teacher: data['teacher'] ?? '',
      group: data['group'] ?? '',
      lastUpdatedDate: data['lastUpdatedDate'] != null
          ? (data['lastUpdatedDate'] as Timestamp).toDate()
          : null,
      scheduledDate: data['scheduledDate'] != null
          ? (data['scheduledDate'] as Timestamp).toDate()
          : null,
    );
  }

  static Map<String, int> _parseTimeSlot(String timeStr) {
    final lower = timeStr.toLowerCase().trim();
    if (lower.isEmpty) return {'startSlot': 1, 'span': 1};

    // Monday-Tuesday Parallel Lab times (usually 11:30 - 1:10 or similar)
    if (lower.contains('11:30') &&
        (lower.contains('1:10') || lower.contains('13:10'))) {
      return {'startSlot': 5, 'span': 2};
    }
    // Labs starting at 2:00 PM spanning to 4:30
    if (lower.contains('2:00') &&
        (lower.contains('4:30') || lower.contains('16:30'))) {
      return {'startSlot': 7, 'span': 3};
    }

    // Single slot mappings
    if (lower.contains('8:00'))
      return {'startSlot': 1, 'span': 2}; // e.g. CHEM 103 8:00 - 9:40
    if (lower.contains('8:50')) return {'startSlot': 2, 'span': 1};
    if (lower.contains('9:50') || lower.contains('10:00 am'))
      return {'startSlot': 3, 'span': 2}; // e.g. PHY 103 9:50-11:30
    if (lower.contains('10:40')) return {'startSlot': 4, 'span': 1};
    if (lower.contains('11:30')) return {'startSlot': 5, 'span': 1};
    if (lower.contains('12:00 pm') || lower.contains('12:20'))
      return {'startSlot': 6, 'span': 1};
    if (lower.contains('2:00') || lower.contains('02:00 pm'))
      return {'startSlot': 7, 'span': 1};
    if (lower.contains('2:50')) return {'startSlot': 8, 'span': 1};
    if (lower.contains('3:40')) return {'startSlot': 9, 'span': 1};
    if (lower.contains('4:30')) return {'startSlot': 10, 'span': 1};

    return {'startSlot': 1, 'span': 1};
  }

  Map<String, dynamic> toMap() {
    return {
      'dayOfWeek': dayOfWeek,
      'subject': subject,
      'subname': subname,
      'room': room,
      'time': time,
      'status': status,
      'startSlot': startSlot,
      'span': span,
      'teacher': teacher,
      'group': group,
      'lastUpdatedDate':
          lastUpdatedDate != null ? Timestamp.fromDate(lastUpdatedDate!) : null,
      'scheduledDate':
          scheduledDate != null ? Timestamp.fromDate(scheduledDate!) : null,
    };
  }
}

class StudyMaterial {
  final String id;
  final String title;
  final String subject;
  final String type; // 'Notes', 'Books', 'Videos', 'Others'
  final String? fileUrl;
  final String? fileName;
  final String extension;
  final String subjectCode;
  final String teacherName;
  final String uploadedBy;

  StudyMaterial({
    required this.id,
    required this.title,
    required this.subject,
    required this.type,
    this.fileUrl,
    this.fileName,
    required this.extension,
    this.subjectCode = '',
    this.teacherName = '',
    this.uploadedBy = '',
  });

  factory StudyMaterial.fromMap(Map<String, dynamic> data, String id) {
    return StudyMaterial(
      id: id,
      title: data['title'] ?? '',
      subject: data['subject'] ?? '',
      type: data['type'] ?? 'Notes',
      fileUrl: data['fileUrl'],
      fileName: data['fileName'],
      extension: data['extension'] ?? '',
      subjectCode: data['subjectCode'] ?? '',
      teacherName: data['teacherName'] ?? '',
      uploadedBy: data['uploadedBy'] ?? '',
    );
  }
}

class CourseDetail {
  final String id;
  final String courseCode;
  final String courseName;
  final String teacherName;
  final String teacherShort;
  final String levelTerm;
  final String totalCredit;
  final List<String> ctMarksUrls;
  final List<String> ctMarksNames;
  final DateTime? timestamp;

  CourseDetail({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.teacherName,
    required this.teacherShort,
    required this.levelTerm,
    required this.totalCredit,
    this.ctMarksUrls = const [],
    this.ctMarksNames = const [],
    this.timestamp,
  });

  String? get ctMarksUrl => ctMarksUrls.isNotEmpty ? ctMarksUrls.first : null;
  String? get ctMarksName =>
      ctMarksNames.isNotEmpty ? ctMarksNames.first : null;

  factory CourseDetail.fromMap(Map<String, dynamic> data, String id) {
    final dynamic rawUrls = data['ctMarksUrls'] ?? data['ctMarksUrl'];
    final dynamic rawNames = data['ctMarksNames'] ?? data['ctMarksName'];

    List<String> urls = [];
    if (rawUrls is String && rawUrls.isNotEmpty) {
      urls = [rawUrls];
    } else if (rawUrls is List) {
      urls = rawUrls.map((e) => e.toString()).toList();
    }

    List<String> names = [];
    if (rawNames is String && rawNames.isNotEmpty) {
      names = [rawNames];
    } else if (rawNames is List) {
      names = rawNames.map((e) => e.toString()).toList();
    }

    return CourseDetail(
      id: id,
      courseCode: data['courseCode'] ?? '',
      courseName: data['courseName'] ?? '',
      teacherName: data['teacherName'] ?? '',
      teacherShort: data['teacherShort'] ?? '',
      levelTerm: data['levelTerm'] ?? '',
      totalCredit: data['totalCredit'] ?? '3.0',
      ctMarksUrls: urls,
      ctMarksNames: names,
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'courseCode': courseCode,
      'courseName': courseName,
      'teacherName': teacherName,
      'teacherShort': teacherShort,
      'levelTerm': levelTerm,
      'totalCredit': totalCredit,
      'ctMarksUrls': ctMarksUrls,
      'ctMarksNames': ctMarksNames,
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
    };
  }
}
