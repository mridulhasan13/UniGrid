/**
 * ============================================================================
 * UniGrid Demo Sandbox Bucket Comprehensive Seeder
 * ============================================================================
 * Purpose: Fills Course Registry, Full Schedule/Routine, Materials, Notices,
 *          and Department Group Chat for 'depts/DEMO/batches/01'
 * ============================================================================
 */

const path = require('path');
const fs = require('fs');

let admin;
try {
  admin = require(path.resolve(__dirname, '../../functions/node_modules/firebase-admin'));
} catch (e) {
  try {
    admin = require('firebase-admin');
  } catch (err) {
    console.error('Could not load firebase-admin. Please run "npm install" inside functions/ directory.');
    process.exit(1);
  }
}

const serviceAccountPath = path.resolve(__dirname, '../../assets/service_account.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('Service account not found at:', serviceAccountPath);
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

const DEPT = 'DEMO';
const BATCH = '01';
const BASE_PATH = `depts/${DEPT}/batches/${BATCH}`;

async function seedComprehensiveDemo() {
  console.log(`🚀 Starting Comprehensive Seeding for: ${BASE_PATH} ...\n`);

  // 1. Config / Theme
  console.log('🎨 1. Setting up Theme Config & Routine Metadata...');
  await db.doc(`${BASE_PATH}/config/app_theme`).set({
    currentTheme: 'Sky Sapphire',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.doc(`${BASE_PATH}/routine_metadata/info`).set({
    university: 'Bangladesh University of Textiles',
    levelTerm: 'Level-3 Term-1',
    department: 'Demo Campus Sandbox',
    batch: '01',
    lastResetDate: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // 2. Course Registry (`courses` collection)
  console.log('📚 2. Seeding Course Registry...');
  const coursesRef = db.collection(`${BASE_PATH}/courses`);
  
  // Clear previous courses in DEMO bucket
  const existingCourses = await coursesRef.get();
  for (const doc of existingCourses.docs) {
    await doc.ref.delete();
  }

  const sampleCourses = [
    {
      courseCode: 'IPE 301',
      courseName: 'Quality Control & Reliability Engineering',
      teacherName: 'Dr. Abdur Rahman',
      teacherShort: 'AR',
      levelTerm: 'Level-3 Term-1',
      totalCredit: '3.0',
      ctMarksUrls: ['https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'],
      ctMarksNames: ['CT-1 Marks Result.pdf'],
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    },
    {
      courseCode: 'IPE 305',
      courseName: 'Manufacturing Processes II',
      teacherName: 'Prof. Mostafa Karim',
      teacherShort: 'MK',
      levelTerm: 'Level-3 Term-1',
      totalCredit: '3.0',
      ctMarksUrls: ['https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'],
      ctMarksNames: ['CT-1 Class Test Evaluation.pdf'],
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    },
    {
      courseCode: 'IPE 309',
      courseName: 'Operations Research & Optimization',
      teacherName: 'Dr. Shahriar Ahmed',
      teacherShort: 'SA',
      levelTerm: 'Level-3 Term-1',
      totalCredit: '3.0',
      ctMarksUrls: [],
      ctMarksNames: [],
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    },
    {
      courseCode: 'IPE 310',
      courseName: 'CAD/CAM Laboratory',
      teacherName: 'Engr. Kamrul Hasan',
      teacherShort: 'KH',
      levelTerm: 'Level-3 Term-1',
      totalCredit: '1.5',
      ctMarksUrls: ['https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'],
      ctMarksNames: ['Lab Assessment 1 Marks.pdf'],
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    },
    {
      courseCode: 'IPE 313',
      courseName: 'Supply Chain & Logistics Management',
      teacherName: 'Dr. Tanvir Chowdhury',
      teacherShort: 'TC',
      levelTerm: 'Level-3 Term-1',
      totalCredit: '3.0',
      ctMarksUrls: [],
      ctMarksNames: [],
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    },
  ];

  for (const c of sampleCourses) {
    await coursesRef.add(c);
  }

  // 3. Weekly Routine / Schedule (`schedule` & `default_schedule`)
  console.log('📅 3. Seeding Live Weekly Schedule & Default Routine...');
  const scheduleRef = db.collection(`${BASE_PATH}/schedule`);
  const defaultScheduleRef = db.collection(`${BASE_PATH}/default_schedule`);

  // Clear existing
  const exSched = await scheduleRef.get();
  for (const doc of exSched.docs) await doc.ref.delete();
  const exDef = await defaultScheduleRef.get();
  for (const doc of exDef.docs) await doc.ref.delete();

  const today = new Date();
  const currentDay = today.getDay(); // 0 is Sunday
  const sunday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - currentDay);
  sunday.setHours(0, 0, 0, 0);

  const sampleSchedule = [
    // Sunday (Day 0)
    {
      dayOffset: 0,
      dayOfWeek: 'Sunday',
      subject: 'IPE 301',
      subname: 'Quality Control & Reliability',
      room: 'Room 402',
      time: '08:00 AM - 09:40 AM',
      status: 'upcoming',
      startSlot: 1,
      span: 2,
      teacher: 'Dr. Abdur Rahman',
      group: 'All',
    },
    {
      dayOffset: 0,
      dayOfWeek: 'Sunday',
      subject: 'IPE 305',
      subname: 'Manufacturing Processes II',
      room: 'Room 405',
      time: '10:00 AM - 11:30 AM',
      status: 'upcoming',
      startSlot: 3,
      span: 2,
      teacher: 'Prof. Mostafa Karim',
      group: 'All',
    },
    // Monday (Day 1)
    {
      dayOffset: 1,
      dayOfWeek: 'Monday',
      subject: 'IPE 309',
      subname: 'Operations Research',
      room: 'Room 402',
      time: '09:50 AM - 11:30 AM',
      status: 'upcoming',
      startSlot: 3,
      span: 2,
      teacher: 'Dr. Shahriar Ahmed',
      group: 'All',
    },
    {
      dayOffset: 1,
      dayOfWeek: 'Monday',
      subject: 'IPE 310',
      subname: 'CAD/CAM Laboratory',
      room: 'CAD Lab 02',
      time: '02:00 PM - 04:30 PM',
      status: 'upcoming',
      startSlot: 7,
      span: 3,
      teacher: 'Engr. Kamrul Hasan',
      group: 'Gr: A',
    },
    // Tuesday (Day 2)
    {
      dayOffset: 2,
      dayOfWeek: 'Tuesday',
      subject: 'IPE 301',
      subname: 'Quality Control (Class Test 1)',
      room: 'Room 402',
      time: '10:00 AM - 11:30 AM',
      status: 'upcoming',
      startSlot: 3,
      span: 2,
      teacher: 'Dr. Abdur Rahman',
      group: 'All',
    },
    {
      dayOffset: 2,
      dayOfWeek: 'Tuesday',
      subject: 'IPE 313',
      subname: 'Supply Chain Management',
      room: 'Room 306',
      time: '12:00 PM - 01:30 PM',
      status: 'upcoming',
      startSlot: 6,
      span: 2,
      teacher: 'Dr. Tanvir Chowdhury',
      group: 'All',
    },
    // Wednesday (Day 3)
    {
      dayOffset: 3,
      dayOfWeek: 'Wednesday',
      subject: 'IPE 305',
      subname: 'Manufacturing Processes II',
      room: 'Room 405',
      time: '08:50 AM - 10:30 AM',
      status: 'upcoming',
      startSlot: 2,
      span: 2,
      teacher: 'Prof. Mostafa Karim',
      group: 'All',
    },
    {
      dayOffset: 3,
      dayOfWeek: 'Wednesday',
      subject: 'IPE 310',
      subname: 'CAD/CAM Laboratory',
      room: 'CAD Lab 02',
      time: '02:00 PM - 04:30 PM',
      status: 'upcoming',
      startSlot: 7,
      span: 3,
      teacher: 'Engr. Kamrul Hasan',
      group: 'Gr: B',
    },
    // Thursday (Day 4)
    {
      dayOffset: 4,
      dayOfWeek: 'Thursday',
      subject: 'IPE 309',
      subname: 'Operations Research Problem Solving',
      room: 'Room 402',
      time: '09:50 AM - 11:30 AM',
      status: 'upcoming',
      startSlot: 3,
      span: 2,
      teacher: 'Dr. Shahriar Ahmed',
      group: 'All',
    },
    {
      dayOffset: 4,
      dayOfWeek: 'Thursday',
      subject: 'IPE 313',
      subname: 'Supply Chain Case Studies',
      room: 'Seminar Room',
      time: '11:40 AM - 01:10 PM',
      status: 'upcoming',
      startSlot: 5,
      span: 2,
      teacher: 'Dr. Tanvir Chowdhury',
      group: 'All',
    },
  ];

  for (const s of sampleSchedule) {
    const classDate = new Date(sunday.getTime() + s.dayOffset * 24 * 60 * 60 * 1000);
    
    // 1. Current week specific dated class
    await scheduleRef.add({
      dayOfWeek: s.dayOfWeek,
      subject: s.subject,
      subname: s.subname,
      room: s.room,
      time: s.time,
      status: s.status,
      startSlot: s.startSlot,
      span: s.span,
      teacher: s.teacher,
      group: s.group,
      scheduledDate: admin.firestore.Timestamp.fromDate(classDate),
      lastUpdatedDate: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Recurring weekly class (null scheduledDate ensures visibility every week)
    await scheduleRef.add({
      dayOfWeek: s.dayOfWeek,
      subject: s.subject,
      subname: s.subname,
      room: s.room,
      time: s.time,
      status: s.status,
      startSlot: s.startSlot,
      span: s.span,
      teacher: s.teacher,
      group: s.group,
      scheduledDate: null,
      lastUpdatedDate: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. Default schedule template
    await defaultScheduleRef.add({
      dayOfWeek: s.dayOfWeek,
      subject: s.subject,
      subname: s.subname,
      room: s.room,
      time: s.time,
      status: s.status,
      startSlot: s.startSlot,
      span: s.span,
      teacher: s.teacher,
      group: s.group,
      scheduledDate: null,
      lastUpdatedDate: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // 4. Announcements
  console.log('📢 4. Seeding Announcements...');
  const annRef = db.collection(`${BASE_PATH}/announcements`);
  const exAnn = await annRef.get();
  for (const doc of exAnn.docs) await doc.ref.delete();

  const sampleAnnouncements = [
    {
      title: 'Welcome to UniGrid Campus Hub',
      content: 'Welcome to the UniGrid digital workspace! Here you can check live daily class routines, access course study materials & CT marksheets, and communicate with your classmates in real time.',
      type: 'Notice',
      postedBy: 'Demo CR (Admin)',
      details: 'Venue: Central Campus Portal',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 2)),
    },
    {
      title: 'Class Test 1 (CT-1) Schedule Announced',
      content: 'Class Test 1 for "Quality Control & Reliability (IPE 301)" will be held on upcoming Tuesday during the second lecture slot. Syllabus covers Chapters 1 to 3.',
      type: 'Urgent',
      postedBy: 'Demo CR (Admin)',
      details: 'Room No: 402 • Time: 10:00 AM',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 24)),
    },
    {
      title: 'Operations Research Lab Guidelines & Groups',
      content: 'The lab group distributions and assignment problem sets for Operations Research (IPE 309) are now available. Please download the problem sheet from the Materials tab.',
      type: 'Material',
      postedBy: 'Demo CR (Admin)',
      details: 'Due Date: Next Thursday',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 48)),
    },
  ];
  for (const a of sampleAnnouncements) await annRef.add(a);

  // 5. Study Materials
  console.log('📁 5. Seeding Study Materials...');
  const matRef = db.collection(`${BASE_PATH}/materials`);
  const exMat = await matRef.get();
  for (const doc of exMat.docs) await doc.ref.delete();

  const sampleMaterials = [
    {
      title: 'Chapter 01 - Fundamentals of Quality Engineering.pdf',
      subject: 'Quality Control & Reliability',
      subjectCode: 'IPE 301',
      teacherName: 'Dr. Abdur Rahman',
      type: 'Notes',
      extension: 'pdf',
      fileUrl: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
      fileName: 'Chapter_01_Quality_Control.pdf',
      uploadedBy: 'Demo CR (Admin)',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 72)),
    },
    {
      title: 'Manufacturing Processes Lecture Slides Part 2.pdf',
      subject: 'Manufacturing Processes II',
      subjectCode: 'IPE 305',
      teacherName: 'Prof. Mostafa Karim',
      type: 'Notes',
      extension: 'pdf',
      fileUrl: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
      fileName: 'Manufacturing_Processes_Ch2.pdf',
      uploadedBy: 'Demo CR (Admin)',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 96)),
    },
    {
      title: 'Linear Programming & Simplex Method Reference Book.pdf',
      subject: 'Operations Research',
      subjectCode: 'IPE 309',
      teacherName: 'Dr. Shahriar Ahmed',
      type: 'Books',
      extension: 'pdf',
      fileUrl: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
      fileName: 'Operations_Research_Handbook.pdf',
      uploadedBy: 'Demo CR (Admin)',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 120)),
    },
    {
      title: 'CAD CAM Lab Manual & G-Code Exercises.pdf',
      subject: 'CAD/CAM Laboratory',
      subjectCode: 'IPE 310',
      teacherName: 'Engr. Kamrul Hasan',
      type: 'Notes',
      extension: 'pdf',
      fileUrl: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
      fileName: 'CAD_CAM_Lab_Manual.pdf',
      uploadedBy: 'Demo CR (Admin)',
      timestamp: admin.firestore.Timestamp.fromDate(new Date(Date.now() - 1000 * 60 * 60 * 140)),
    },
  ];
  for (const m of sampleMaterials) await matRef.add(m);

  // 6. Department Group Chat Messages (`chat_messages` collection)
  console.log('💬 6. Seeding Department Group Chat Room (`chat_messages`)...');
  const chatMessagesRef = db.collection(`${BASE_PATH}/chat_messages`);
  const exChat = await chatMessagesRef.get();
  for (const doc of exChat.docs) await doc.ref.delete();

  const t = Date.now();
  const sampleMessages = [
    {
      id: 'demo_msg_01',
      authorId: 'demo_cr_001',
      authorName: 'Mahmudul Hasan (CR)',
      authorPhoto: '',
      isCR: true,
      text: 'Good morning everyone! ☀️ Please check the Materials tab — Chapter 1 slides and CT-1 schedule for IPE 301 are now uploaded.',
      type: 'text',
      isUnsent: false,
      isDeleted: false,
      seenBy: [],
      preciseTime: (t - 3600000 * 6) * 1000,
      createdAt: admin.firestore.Timestamp.fromDate(new Date(t - 3600000 * 6)),
    },
    {
      id: 'demo_msg_02',
      authorId: 'demo_student_002',
      authorName: 'Sarah Jenkins',
      authorPhoto: '',
      isCR: false,
      text: 'Thank you! Is the CT-1 on Tuesday covering the problem set from Chapter 2 as well?',
      type: 'text',
      isUnsent: false,
      isDeleted: false,
      seenBy: [],
      preciseTime: (t - 3600000 * 5) * 1000,
      createdAt: admin.firestore.Timestamp.fromDate(new Date(t - 3600000 * 5)),
    },
    {
      id: 'demo_msg_03',
      authorId: 'demo_cr_001',
      authorName: 'Mahmudul Hasan (CR)',
      authorPhoto: '',
      isCR: true,
      text: 'Yes Sarah, Sir mentioned Chapters 1 and 2 will both be included in the test.',
      type: 'text',
      isUnsent: false,
      isDeleted: false,
      seenBy: [],
      replyTo: {
        id: 'demo_msg_02',
        text: 'Thank you! Is the CT-1 on Tuesday covering the problem set from Chapter 2 as well?',
        authorName: 'Sarah Jenkins',
      },
      preciseTime: (t - 3600000 * 4) * 1000,
      createdAt: admin.firestore.Timestamp.fromDate(new Date(t - 3600000 * 4)),
    },
    {
      id: 'demo_msg_04',
      authorId: 'demo_student_003',
      authorName: 'Alex Rahman',
      authorPhoto: '',
      isCR: false,
      text: 'Got it! Also a quick reminder for Group A students: CAD/CAM lab starts at 2:00 PM sharp in Lab 02.',
      type: 'text',
      isUnsent: false,
      isDeleted: false,
      seenBy: [],
      preciseTime: (t - 3600000 * 2) * 1000,
      createdAt: admin.firestore.Timestamp.fromDate(new Date(t - 3600000 * 2)),
    },
    {
      id: 'demo_msg_05',
      authorId: 'demo_student_004',
      authorName: 'Nusrat Jahan',
      authorPhoto: '',
      isCR: false,
      text: 'Has anyone downloaded the Operations Research assignment sheet yet?',
      type: 'text',
      isUnsent: false,
      isDeleted: false,
      seenBy: [],
      preciseTime: (t - 3600000 * 1) * 1000,
      createdAt: admin.firestore.Timestamp.fromDate(new Date(t - 3600000 * 1)),
    },
    {
      id: 'demo_msg_06',
      authorId: 'demo_cr_001',
      authorName: 'Mahmudul Hasan (CR)',
      authorPhoto: '',
      isCR: true,
      text: 'Yes, it is available in Materials under IPE 309. Feel free to ask if you have any questions! 🚀',
      type: 'text',
      isUnsent: false,
      isDeleted: false,
      seenBy: [],
      preciseTime: (t - 1800000) * 1000,
      createdAt: admin.firestore.Timestamp.fromDate(new Date(t - 1800000)),
    },
  ];

  for (const m of sampleMessages) {
    await chatMessagesRef.add(m);
  }

  // 7. Ensure Reviewer User is Pre-Approved in Firestore
  console.log('👤 7. Syncing Demo Reviewer Account...');
  const reviewerEmail = 'demo.reviewer@unigrid.app';
  const reviewerUid = 'google_play_reviewer_demo_uid';

  try {
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(reviewerEmail);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        userRecord = await admin.auth().createUser({
          uid: reviewerUid,
          email: reviewerEmail,
          password: 'UniGrid@2026',
          displayName: 'Google Reviewer',
          emailVerified: true,
        });
      } else {
        throw err;
      }
    }

    await db.collection('users').doc(userRecord.uid).set({
      email: reviewerEmail,
      name: 'Google Reviewer',
      department: DEPT,
      batch: BATCH,
      studentId: 'DEMO-2026',
      phoneNumber: '+8801700000000',
      photoUrl: '',
      isApproved: true,
      isAdmin: false,
      isCR: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log(`   ✅ Reviewer profile linked to ${DEPT} / ${BATCH}.`);
  } catch (authErr) {
    console.warn(`   Auth sync notice:`, authErr.message);
  }

  console.log('\n============================================================');
  console.log('🎉 Full Course Registry, Routine & Chat Seeding Completed!');
  console.log(`Bucket: ${BASE_PATH}`);
  console.log(`- 5 Courses with CT Mark Badges in Course Registry`);
  console.log(`- 10 Scheduled Weekly Classes in Calendar Routine`);
  console.log(`- 4 Study Material PDFs in Materials tab`);
  console.log(`- 6 Group Chat Messages with replies in Chat Room`);
  console.log('============================================================\n');
}

seedComprehensiveDemo().then(() => {
  process.exit(0);
}).catch((err) => {
  console.error('Seeding error:', err);
  process.exit(1);
});
