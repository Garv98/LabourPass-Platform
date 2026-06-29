import { Routes, Route, Navigate } from 'react-router-dom'
import { RequireAuth } from './components/RequireAuth'
import { EmployerLayout } from './components/EmployerLayout'
import { AdminLayout } from './components/AdminLayout'
import { ConfigGate } from './components/ConfigGate'

import Landing from './pages/Landing'
import PhonePage from './pages/PhonePage'

import EmployerDashboard from './pages/employer/Dashboard'
import Workers from './pages/employer/Workers'
import WorkerDetail from './pages/employer/WorkerDetail'
import Worksites from './pages/employer/Worksites'
import Attendance from './pages/employer/Attendance'
import Wages from './pages/employer/Wages'
import Certificates from './pages/employer/Certificates'
import Trust from './pages/employer/Trust'

import AdminDashboard from './pages/admin/Dashboard'
import AdminEmployers from './pages/admin/Employers'
import AdminWorkers from './pages/admin/Workers'
import AdminDisputes from './pages/admin/Disputes'
import AdminSms from './pages/admin/Sms'
import AdminTrust from './pages/admin/Trust'
import AdminAnalytics from './pages/admin/Analytics'

import VerifyPassbook from './pages/verify/Passbook'
import VerifyCertificate from './pages/verify/Certificate'

export default function App() {
  return (
    <ConfigGate>
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="/login" element={<Navigate to="/?role=employer" replace />} />
        <Route path="/admin/login" element={<Navigate to="/?role=admin" replace />} />
        <Route path="/phone" element={<PhonePage />} />

        <Route
          path="/employer"
          element={
            <RequireAuth role="employer">
              <EmployerLayout />
            </RequireAuth>
          }
        >
          <Route index element={<EmployerDashboard />} />
          <Route path="workers" element={<Workers />} />
          <Route path="workers/:id" element={<WorkerDetail />} />
          <Route path="worksites" element={<Worksites />} />
          <Route path="attendance" element={<Attendance />} />
          <Route path="wages" element={<Wages />} />
          <Route path="certificates" element={<Certificates />} />
          <Route path="trust" element={<Trust />} />
        </Route>

        <Route
          path="/admin"
          element={
            <RequireAuth role="admin">
              <AdminLayout />
            </RequireAuth>
          }
        >
          <Route index element={<AdminDashboard />} />
          <Route path="employers" element={<AdminEmployers />} />
          <Route path="workers" element={<AdminWorkers />} />
          <Route path="disputes" element={<AdminDisputes />} />
          <Route path="sms" element={<AdminSms />} />
          <Route path="trust" element={<AdminTrust />} />
          <Route path="analytics" element={<AdminAnalytics />} />
        </Route>

        <Route path="/verify/passbook/:publicId" element={<VerifyPassbook />} />
        <Route path="/verify/cert/:certNo" element={<VerifyCertificate />} />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </ConfigGate>
  )
}
