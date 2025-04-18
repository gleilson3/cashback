import { Outlet, useNavigate } from 'react-router-dom';
import { CreditCard, LogOut, User } from 'lucide-react';
import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import type { Admin } from '../types';
import AdminLogin from '../pages/admin/Login';
import toast from 'react-hot-toast';

export default function AdminLayout() {
  const [adminData, setAdminData] = useState<Admin | null>(null);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    checkSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      if (event === 'SIGNED_IN' && session?.user) {
        await fetchAdminData(session.user.id);
      } else if (event === 'SIGNED_OUT' || event === 'TOKEN_REFRESHED') {
        setAdminData(null);
      }
    });

    return () => {
      subscription.unsubscribe();
    };
  }, []);

  const checkSession = async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (session?.user) {
        await fetchAdminData(session.user.id);
      }
    } catch (error) {
      console.error('Error checking session:', error);
    } finally {
      setLoading(false);
    }
  };

  const fetchAdminData = async (userId: string) => {
    try {
      const { data, error } = await supabase
        .from('admins')
        .select('*')
        .eq('id', userId)
        .single();

      if (error) throw error;

      if (data) {
        setAdminData(data as Admin);
      } else {
        await handleAdminLogout();
      }
    } catch (error) {
      console.error('Error fetching admin data:', error);
      await handleAdminLogout();
    }
  };

  const handleAdminLogout = async () => {
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      
      setAdminData(null);
      navigate('/admin/login');
      toast.success('Logout realizado com sucesso!');
    } catch (error) {
      console.error('Error logging out:', error);
      toast.error('Erro ao fazer logout');
    }
  };

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
    </div>;
  }

  if (!adminData) {
    return <AdminLogin />;
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary-50 to-secondary-50">
      <header className="header">
        <div className="header-container">
          <div className="header-content">
            <h1 className="header-title">
              <CreditCard className="w-5 sm:w-6 h-5 sm:h-6 text-primary-600" />
              Área Administrativa
            </h1>
            <div className="header-actions">
              <span className="hidden sm:flex text-sm items-center gap-2">
                <User className="w-4 h-4" />
                {adminData.email}
              </span>
              <button
                onClick={handleAdminLogout}
                className="btn-secondary !py-2"
              >
                <LogOut className="w-4 h-4" />
                <span className="hidden sm:inline ml-2">Sair</span>
              </button>
            </div>
          </div>
        </div>
      </header>

      <main className="container mx-auto px-4 py-6 sm:py-8">
        <Outlet />
      </main>
    </div>
  );
}