import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

const en = {
  app: 'LabourPass',
  tagline: 'Digital Work Identity & Wage Protection',
  dashboard: 'Dashboard',
  workers: 'Workers',
  worksites: 'Worksites',
  attendance: 'Attendance',
  wages: 'Wages',
  certificates: 'Certificates',
  trust: 'Trust Score',
  totalWorkers: 'Total Workers',
  activeToday: 'Active Today',
  wagesThisMonth: 'Wages (this month)',
  markAttendance: 'Mark Attendance',
  recordWage: 'Record Wage',
  addWorker: 'Add Worker',
  registerWorker: 'Register Worker',
  present: 'Present',
  half: 'Half-day',
  absent: 'Absent',
  submitAttendance: 'Submit Attendance',
  logout: 'Logout',
  verifiedPayer: 'Verified Payer',
}

const hi = {
  app: 'लेबरपास',
  tagline: 'डिजिटल कार्य पहचान और वेतन सुरक्षा',
  dashboard: 'डैशबोर्ड',
  workers: 'मज़दूर',
  worksites: 'साइट',
  attendance: 'हाज़िरी',
  wages: 'वेतन',
  certificates: 'प्रमाणपत्र',
  trust: 'भरोसा स्कोर',
  totalWorkers: 'कुल मज़दूर',
  activeToday: 'आज उपस्थित',
  wagesThisMonth: 'इस माह वेतन',
  markAttendance: 'हाज़िरी लगाएं',
  recordWage: 'वेतन दर्ज करें',
  addWorker: 'मज़दूर जोड़ें',
  registerWorker: 'मज़दूर पंजीकरण',
  present: 'उपस्थित',
  half: 'आधा दिन',
  absent: 'अनुपस्थित',
  submitAttendance: 'हाज़िरी जमा करें',
  logout: 'लॉगआउट',
  verifiedPayer: 'सत्यापित भुगतानकर्ता',
}

i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, hi: { translation: hi } },
  lng: localStorage.getItem('lp_lang') || 'en',
  fallbackLng: 'en',
  interpolation: { escapeValue: false },
})

export default i18n
