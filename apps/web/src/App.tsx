import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClientProvider, QueryClient } from '@tanstack/react-query'
import Dashboard from './pages/Dashboard'
import Devices from './pages/Devices'
import Sessions from './pages/Sessions'
import NetworkSettings from './pages/NetworkSettings'
import AuditLog from './pages/AuditLog'
import Settings from './pages/Settings'
import JoinPage from './pages/JoinPage'
import AppShell from './components/AppShell'

const queryClient = new QueryClient()

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route path="/join/:token" element={<JoinPage />} />
          <Route element={<AppShell />}>
            <Route path="/" element={<Dashboard />} />
            <Route path="/devices" element={<Devices />} />
            <Route path="/sessions" element={<Sessions />} />
            <Route path="/network" element={<NetworkSettings />} />
            <Route path="/audit" element={<AuditLog />} />
            <Route path="/settings" element={<Settings />} />
            <Route path="*" element={<Navigate to="/" />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  )
}

export default App
