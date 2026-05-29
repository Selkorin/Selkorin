import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Layout from './components/layout/Layout';
import Dashboard from './pages/Dashboard';
import ContentManagement from './pages/ContentManagement';
import CompetitorAnalysis from './pages/CompetitorAnalysis';
import LeadGeneration from './pages/LeadGeneration';
import Analytics from './pages/Analytics';
import Settings from './pages/Settings';
import NotFound from './pages/NotFound';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Dashboard />} />
          <Route path="/content" element={<ContentManagement />} />
          <Route path="/competitors" element={<CompetitorAnalysis />} />
          <Route path="/leads" element={<LeadGeneration />} />
          <Route path="/analytics" element={<Analytics />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
