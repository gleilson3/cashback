import React, { useState, useEffect } from 'react';
import { ChevronLeft, ChevronRight, ShoppingBag, Gift, CheckCircle2, XCircle, Users, TrendingUp, Wallet, Clock, AlertTriangle, FileText, Lock, BarChart3, X, MapPin, UserCircle, Download, Calendar, Navigation } from 'lucide-react';
import DateRangeFilter from '../../components/DateRangeFilter';
import LocationCapture from './LocationCapture';
import { supabase } from '../../lib/supabase';
import toast from 'react-hot-toast';
import { generateCustomerReport } from '../../utils/reportGenerator';
import * as XLSX from 'xlsx';

export default function Dashboard() {
  const [activeTab, setActiveTab] = useState('purchases');
  const [showLocationCapture, setShowLocationCapture] = useState(false);
  const [dateRange, setDateRange] = useState('today');
  const [customStartDate, setCustomStartDate] = useState(new Date());
  const [customEndDate, setCustomEndDate] = useState(new Date());
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [loading, setLoading] = useState(false);
  const [currentTransactions, setCurrentTransactions] = useState([]);
  const [reportData, setReportData] = useState(null);
  const [showAdvancedReport, setShowAdvancedReport] = useState(false);
  const [showPasswordModal, setShowPasswordModal] = useState(false);
  const [password, setPassword] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [metrics, setMetrics] = useState({
    totalCustomers: 0,
    activeCustomers: 0,
    totalTransactions: 0,
    averageTicket: 0,
    totalRevenue: 0,
    totalCashback: 0,
    redemptionRate: 0,
    atRiskCustomers: 0
  });

  useEffect(() => {
    const getAdminData = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (user) {
          setAdminEmail(user.email);
        }
      } catch (error) {
        console.error('Error loading admin data:', error);
        toast.error('Erro ao carregar dados: ' + error.message);
      }
    };
    getAdminData();
  }, []);

  const loadTransactions = async () => {
    try {
      setLoading(true);

      let startDate = new Date();
      let endDate = new Date();

      switch (dateRange) {
        case 'today':
          startDate.setHours(0, 0, 0, 0);
          endDate.setHours(23, 59, 59, 999);
          break;
        case 'yesterday':
          startDate.setDate(startDate.getDate() - 1);
          startDate.setHours(0, 0, 0, 0);
          endDate = new Date(startDate);
          endDate.setHours(23, 59, 59, 999);
          break;
        case 'last7days':
          startDate.setDate(startDate.getDate() - 7);
          startDate.setHours(0, 0, 0, 0);
          endDate.setHours(23, 59, 59, 999);
          break;
        case 'last30days':
          startDate.setDate(startDate.getDate() - 30);
          startDate.setHours(0, 0, 0, 0);
          endDate.setHours(23, 59, 59, 999);
          break;
        case 'thisMonth':
          startDate = new Date(startDate.getFullYear(), startDate.getMonth(), 1);
          endDate = new Date(endDate.getFullYear(), endDate.getMonth() + 1, 0, 23, 59, 59, 999);
          break;
        case 'lastMonth':
          startDate = new Date(startDate.getFullYear(), startDate.getMonth() - 1, 1);
          endDate = new Date(endDate.getFullYear(), endDate.getMonth(), 0, 23, 59, 59, 999);
          break;
        case 'custom':
          startDate = new Date(customStartDate);
          startDate.setHours(0, 0, 0, 0);
          endDate = new Date(customEndDate);
          endDate.setHours(23, 59, 59, 999);
          break;
      }

      let query = supabase
        .from('transactions')
        .select(`
          *,
          customers (
            id,
            name,
            phone,
            balance
          ),
          stores (
            id,
            name,
            code
          )
        `)
        .gte('created_at', startDate.toISOString())
        .lte('created_at', endDate.toISOString())
        .order('created_at', { ascending: false });

      const { data: transactions, error: transactionsError } = await query;

      if (transactionsError) throw transactionsError;

      if (!transactions) {
        setCurrentTransactions([]);
        return;
      }

      setCurrentTransactions(transactions);
      setTotalPages(Math.ceil(transactions.length / 10));

      const approvedPurchases = transactions.filter(t => t.type === 'purchase' && t.status === 'approved');
      const approvedRedemptions = transactions.filter(t => t.type === 'redemption' && t.status === 'approved');

      const totalRevenue = approvedPurchases.reduce((sum, t) => sum + Number(t.amount), 0);
      const totalCashback = approvedPurchases.reduce((sum, t) => sum + Number(t.cashback_amount), 0);
      const totalRedemptions = approvedRedemptions.reduce((sum, t) => sum + Number(t.amount), 0);

      let customerQuery = supabase.from('customers').select('*');
      
      const storeCustomerIds = [...new Set(transactions.map(t => t.customer_id))];
      if (storeCustomerIds.length > 0) {
        customerQuery = customerQuery.in('id', storeCustomerIds);
      }

      const { data: customers, error: customersError } = await customerQuery;

      if (customersError) throw customersError;

      const customerMetrics = new Map();
      
      customers.forEach(customer => {
        const customerTransactions = transactions.filter(t => t.customer_id === customer.id);
        
        const metrics = {
          totalPurchases: customerTransactions.filter(t => t.type === 'purchase' && t.status === 'approved').length,
          totalSpent: customerTransactions
            .filter(t => t.type === 'purchase' && t.status === 'approved')
            .reduce((sum, t) => sum + Number(t.amount), 0),
          lastPurchase: customerTransactions
            .filter(t => t.type === 'purchase' && t.status === 'approved')
            .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))[0]?.created_at,
          status: 'inactive'
        };

        if (metrics.lastPurchase) {
          const daysSinceLastPurchase = Math.floor(
            (new Date() - new Date(metrics.lastPurchase)) / (1000 * 60 * 60 * 24)
          );

          if (daysSinceLastPurchase <= 3) {
            metrics.status = 'active';
          } else if (daysSinceLastPurchase <= 7) {
            metrics.status = 'at_risk';
          }
        }

        customerMetrics.set(customer.id, metrics);
      });

      const activeCustomers = Array.from(customerMetrics.values()).filter(m => m.status === 'active').length;
      const atRiskCustomers = Array.from(customerMetrics.values()).filter(m => m.status === 'at_risk').length;
      const averageTicket = approvedPurchases.length > 0 ? totalRevenue / approvedPurchases.length : 0;
      const redemptionRate = totalCashback > 0 ? (totalRedemptions / totalCashback) * 100 : 0;

      setMetrics({
        totalCustomers: customers.length,
        activeCustomers,
        totalTransactions: approvedPurchases.length,
        averageTicket,
        totalRevenue,
        totalCashback,
        redemptionRate,
        atRiskCustomers
      });

      setReportData({
        customers,
        customerMetrics,
        transactions: transactions.filter(t => 
          activeTab === 'purchases' ? t.type === 'purchase' : t.type === 'redemption'
        )
      });

    } catch (error) {
      console.error('Error loading transactions:', error);
      toast.error('Erro ao carregar transações: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = async (transaction, newStatus) => {
    try {
      // Get customer balance before approving redemption
      if (transaction.type === 'redemption' && newStatus === 'approved') {
        const { data: balance } = await supabase
          .from('customer_balances')
          .select('available_balance')
          .eq('customer_id', transaction.customer_id)
          .single();

        if (!balance || balance.available_balance < transaction.amount) {
          toast.error(
            <div className="flex flex-col gap-2">
              <p>Não é possível aprovar o resgate: saldo insuficiente do cliente</p>
              <p className="text-sm text-red-600">
                Saldo disponível: R$ {balance?.available_balance?.toFixed(2) || '0,00'}
                <br />
                Valor do resgate: R$ {transaction.amount.toFixed(2)}
              </p>
            </div>,
            { duration: 5000 }
          );
          return;
        }
      }

      const { error } = await supabase
        .from('transactions')
        .update({ 
          status: newStatus,
          attendant_name: adminEmail
        })
        .eq('id', transaction.id);

      if (error) throw error;

      toast.success('Status atualizado com sucesso!');
      loadTransactions();
    } catch (error) {
      console.error('Error updating status:', error);
      toast.error('Erro ao atualizar status: ' + error.message);
    }
  };

  const handlePasswordSubmit = (e) => {
    e.preventDefault();
    if (password === 'Gle0103,,#*') {
      setShowPasswordModal(false);
      setShowAdvancedReport(true);
      setPassword('');
    } else {
      toast.error('Senha incorreta');
    }
  };

  const handleExportExcel = async () => {
    try {
      if (!reportData?.customers) {
        toast.error('Nenhum dado disponível para exportar');
        return;
      }

      // Filter customers based on status
      const filteredCustomers = reportData.customers
        .filter(customer => {
          const metrics = reportData.customerMetrics.get(customer.id);
          if (!metrics) return false;
          
          const daysSinceLastPurchase = metrics.lastPurchase
            ? Math.floor((new Date() - new Date(metrics.lastPurchase)) / (1000 * 60 * 60 * 24))
            : null;

          switch (statusFilter) {
            case 'active':
              return daysSinceLastPurchase !== null && daysSinceLastPurchase <= 3;
            case 'at_risk':
              return daysSinceLastPurchase !== null && daysSinceLastPurchase > 3 && daysSinceLastPurchase <= 7;
            case 'inactive':
              return daysSinceLastPurchase === null || daysSinceLastPurchase > 7;
            default:
              return true;
          }
        });

      // Prepare Excel data with raw phone numbers and additional columns
      const excelData = filteredCustomers.map(customer => ({
        Nome: customer.name || 'Não informado',
        Telefone: customer.phone, // Raw phone number without formatting
        Email: customer.email || 'Não informado',
        Var1: '', // Empty column
        Var2: '', // Empty column
        Var3: '' // Empty column
      }));

      // Create workbook and worksheet
      const wb = XLSX.utils.book_new();
      const ws = XLSX.utils.json_to_sheet(excelData);

      // Set column widths
      const colWidths = [
        { wch: 30 }, // Nome
        { wch: 15 }, // Telefone
        { wch: 30 }, // Email
        { wch: 15 }, // Var1
        { wch: 15 }, // Var2
        { wch: 15 }  // Var3
      ];
      ws['!cols'] = colWidths;

      // Add worksheet to workbook
      XLSX.utils.book_append_sheet(wb, ws, 'Cadastros');

      // Generate Excel file
      XLSX.writeFile(wb, `cadastros_${statusFilter}.xlsx`);

      toast.success('Arquivo Excel gerado com sucesso!');
    } catch (error) {
      console.error('Error exporting Excel:', error);
      toast.error('Erro ao exportar Excel: ' + error.message);
    }
  };

  useEffect(() => {
    loadTransactions();
  }, [dateRange, activeTab]);

  const handlePreviousPage = () => {
    if (currentPage > 1) {
      setCurrentPage(currentPage - 1);
    }
  };

  const handleNextPage = () => {
    if (currentPage < totalPages) {
      setCurrentPage(currentPage + 1);
    }
  };

  const formatDateTime = (dateString) => {
    return new Date(dateString).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const formatCurrency = (value) => {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL'
    }).format(value);
  };

  const getLastActivity = (customer, metrics) => {
    if (!metrics.lastPurchase) return 'Nunca comprou';
    
    const days = Math.floor(
      (new Date() - new Date(metrics.lastPurchase)) / (1000 * 60 * 60 * 24)
    );

    if (days === 0) return 'Hoje';
    if (days === 1) return 'Ontem';
    return `${days} dias atrás`;
  };

  return (
    <div className="p-6">
      <div className="space-y-6">
        <div className="bg-white rounded-lg shadow p-4 flex items-center justify-between">
          <DateRangeFilter
            dateRange={dateRange}
            setDateRange={setDateRange}
            customStartDate={customStartDate}
            setCustomStartDate={setCustomStartDate}
            customEndDate={customEndDate}
            setCustomEndDate={setCustomEndDate}
            onDateChange={loadTransactions}
          />
          <div className="flex gap-2">
            <button
              onClick={() => setShowLocationCapture(true)}
              className="btn-secondary py-2 px-4 text-sm flex items-center gap-2"
            >
              <Navigation className="w-4 h-4" />
              Localização
            </button>
            <button
              onClick={() => setShowPasswordModal(true)}
              className={`btn-primary py-2 px-4 text-sm flex items-center gap-2 ${
                showAdvancedReport ? 'bg-purple-700' : ''
              }`}
            >
              <BarChart3 className="w-4 h-4" />
              Relatório Avançado
            </button>
          </div>
        </div>

        {/* Location Capture Modal */}
        {showLocationCapture && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto">
              <div className="p-4 border-b flex items-center justify-between">
                <h2 className="text-lg font-semibold">Capturar Localização</h2>
                <button
                  onClick={() => setShowLocationCapture(false)}
                  className="text-gray-400 hover:text-gray-600"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
              <div className="p-4">
                <LocationCapture />
              </div>
            </div>
          </div>
        )}

        {showPasswordModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
            <div className="bg-white rounded-lg p-6 max-w-md w-full mx-4">
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-lg font-semibold flex items-center gap-2">
                  <Lock className="w-5 h-5 text-purple-600" />
                  Acesso Restrito
                </h3>
                <button
                  onClick={() => {
                    setShowPasswordModal(false);
                    setPassword('');
                  }}
                  className="text-gray-400 hover:text-gray-600"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
              <form onSubmit={handlePasswordSubmit}>
                <div className="mb-4">
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Senha
                  </label>
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                    placeholder="Digite a senha"
                    required
                  />
                </div>
                <div className="flex gap-2">
                  <button
                    type="submit"
                    className="btn-primary flex-1 py-2"
                  >
                    Acessar
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setShowPasswordModal(false);
                      setPassword('');
                    }}
                    className="btn-secondary flex-1 py-2"
                  >
                    Cancelar
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {showAdvancedReport ? (
          <div className="space-y-6">
            <div className="bg-white rounded-lg shadow-lg overflow-hidden">
              <div className="p-4 border-b bg-purple-50">
                <h2 className="text-lg font-semibold text-purple-900 flex items-center gap-2">
                  <BarChart3 className="w-5 h-5 text-purple-600" />
                  Métricas Gerais
                </h2>
              </div>
              <div className="p-6">
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                  <div className="bg-gradient-to-br from-purple-50 to-white rounded-xl shadow-md p-6 border border-purple-100">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center gap-2">
                        <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                          <Users className="w-5 h-5 text-purple-600" />
                        </div>
                        <h3 className="font-medium text-gray-900">Clientes</h3>
                      </div>
                      <span className="text-2xl font-bold text-gray-900">{metrics.totalCustomers}</span>
                    </div>
                    <div className="space-y-2">
                      <div className="flex items-center justify-between text-sm">
                        <div className="flex items-center gap-2">
                          <div className="w-3 h-3 rounded-full bg-green-500" />
                          <span className="text-gray-600">Ativos</span>
                        </div>
                        <span className="font-medium text-green-600">{metrics.activeCustomers}</span>
                      </div>
                      <div className="flex items-center justify-between text-sm">
                        <div className="flex items-center gap-2">
                          <div className="w-3 h-3 rounded-full bg-yellow-500" />
                          <span className="text-gray-600">Em risco</span>
                        </div>
                        <span className="font-medium text-yellow-600">{metrics.atRiskCustomers}</span>
                      </div>
                    </div>
                  </div>

                  <div className="bg-gradient-to-br from-purple-50 to-white rounded-xl shadow-md p-6 border border-purple-100">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center gap-2">
                        <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                          <TrendingUp className="w-5 h-5 text-purple-600" />
                        </div>
                        <h3 className="font-medium text-gray-900">Faturamento</h3>
                      </div>
                      <span className="text-2xl font-bold text-gray-900">{formatCurrency(metrics.totalRevenue)}</span>
                    </div>
                    <div className="space-y-2">
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-600">Ticket Médio</span>
                        <span className="font-medium text-gray-900">{formatCurrency(metrics.averageTicket)}</span>
                      </div>
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-600">Transações</span>
                        <span className="font-medium text-gray-900">{metrics.totalTransactions}</span>
                      </div>
                    </div>
                  </div>

                  <div className="bg-gradient-to-br from-purple-50 to-white rounded-xl shadow-md p-6 border border-purple-100">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center gap-2">
                        <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                          <Wallet className="w-5 h-5 text-purple-600" />
                        </div>
                        <h3 className="font-medium text-gray-900">Cashback</h3>
                      </div>
                      <span className="text-2xl font-bold text-gray-900">{formatCurrency(metrics.totalCashback)}</span>
                    </div>
                    <div className="space-y-2">
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-600">Taxa de Resgate</span>
                        <span className="font-medium text-gray-900">{metrics.redemptionRate.toFixed(1)}%</span>
                      </div>
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-600">Média por Cliente</span>
                        <span className="font-medium text-gray-900">
                          {formatCurrency(metrics.totalCustomers > 0 ? metrics.totalCashback / metrics.totalCustomers : 0)}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="bg-gradient-to-br from-purple-50 to-white rounded-xl shadow-md p-6 border border-purple-100">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center gap-2">
                        <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                          <AlertTriangle className="w-5 h-5 text-purple-600" />
                        </div>
                        <h3 className="font-medium text-gray-900">Alertas</h3>
                      </div>
                      <span className="text-2xl font-bold text-yellow-600">{metrics.atRiskCustomers}</span>
                    </div>
                    <div className="space-y-2">
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-600">Clientes em Risco</span>
                        <span className="font-medium text-yellow-600">{metrics.atRiskCustomers}</span>
                      </div>
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-600">Taxa de Risco</span>
                        <span className="font-medium text-yellow-600">
                          {metrics.totalCustomers > 0 ? ((metrics.atRiskCustomers / metrics.totalCustomers) * 100).toFixed(1) : 0}%
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-lg shadow-lg overflow-hidden">
              <div className="p-4 border-b bg-purple-50 flex items-center justify-between">
                <h2 className="text-lg font-semibold text-purple-900 flex items-center gap-2">
                  <FileText className="w-5 h-5 text-purple-600" />
                  Perfil de Compra dos Clientes
                </h2>
                <div className="flex gap-4">
                  <select
                    value={statusFilter}
                    onChange={(e) => setStatusFilter(e.target.value)}
                    className="bg-white border border-purple-200 rounded-lg px-3 py-2 text-sm"
                  >
                    <option value="all">Todos os Clientes</option>
                    <option value="active">Clientes Ativos</option>
                    <option value="at_risk">Clientes em Risco</option>
                    <option value="inactive">Clientes Inativos</option>
                  </select>
                  <button
                    onClick={handleExportExcel}
                    className="btn-secondary py-2 px-4 text-sm flex items-center gap-2 bg-white"
                  >
                    <Download className="w-4 h-4" />
                    Exportar Excel
                  </button>
                </div>
              </div>

              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="text-left border-b bg-gray-50">
                      <th className="p-4 text-sm font-medium text-gray-500">Cliente</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Ticket Médio</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Total Compras</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Total Gasto</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Cashback Acumulado</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Última Compra</th>
                    </tr>
                  </thead>
                  <tbody>
                    {reportData?.customers
                      .sort((a, b) => {
                        const metricsA = reportData.customerMetrics.get(a.id);
                        const metricsB = reportData.customerMetrics.get(b.id);
                        return metricsB?.totalSpent - metricsA?.totalSpent;
                      })
                      .filter(customer => {
                        const metrics = reportData.customerMetrics.get(customer.id);
                        if (!metrics) return false;
                        
                        const daysSinceLastPurchase = metrics.lastPurchase
                          ? Math.floor((new Date() - new Date(metrics.lastPurchase)) / (1000 * 60 * 60 * 24))
                          : null;

                        switch (statusFilter) {
                          case 'active':
                            return daysSinceLastPurchase !== null && daysSinceLastPurchase <= 3;
                          case 'at_risk':
                            return daysSinceLastPurchase !== null && daysSinceLastPurchase > 3 && daysSinceLastPurchase <= 7;
                          case 'inactive':
                            return daysSinceLastPurchase === null || daysSinceLastPurchase > 7;
                          default:
                            return true;
                        }
                      })
                      .map(customer => {
                        const metrics = reportData.customerMetrics.get(customer.id);
                        if (!metrics) return null;

                        const averageTicket = metrics.totalPurchases > 0 
                          ? metrics.totalSpent / metrics.totalPurchases 
                          : 0;

                        return (
                          <tr key={customer.id} className="border-b hover:bg-purple-50/50 transition-colors">
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {customer.name || 'Não informado'}
                              </div>
                              <div className="text-sm text-gray-500">{customer.phone}</div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {formatCurrency(averageTicket)}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {metrics.totalPurchases}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {formatCurrency(metrics.totalSpent)}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-purple-600">
                                {formatCurrency(metrics.totalSpent * 0.05)}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="text-gray-600">
                                {metrics.lastPurchase 
                                  ? formatDateTime(metrics.lastPurchase)
                                  : 'Nunca comprou'}
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="bg-white rounded-lg shadow-lg overflow-hidden">
              <div className="p-4 border-b bg-purple-50">
                <h2 className="text-lg font-semibold text-purple-900 flex items-center gap-2">
                  <Users className="w-5 h-5 text-purple-600" />
                  Clientes Ativos
                </h2>
              </div>

              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="text-left border-b bg-gray-50">
                      <th className="p-4 text-sm font-medium text-gray-500">Status</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Nome</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Telefone</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Última Atividade</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Total de Compras</th>
                      <th className="p-4 text-sm font-medium text-gray-500">Total Gasto</th>
                    </tr>
                  </thead>
                  <tbody>
                    {reportData?.customers
                      .sort((a, b) => {
                        const metricsA = reportData.customerMetrics.get(a.id);
                        const metricsB = reportData.customerMetrics.get(b.id);
                        const lastActivityA = metricsA?.lastPurchase || new Date(0);
                        const lastActivityB = metricsB?.lastPurchase || new Date(0);
                        return new Date(lastActivityB).getTime() - new Date(lastActivityA).getTime();
                      })
                      .filter(customer => {
                        const metrics = reportData.customerMetrics.get(customer.id);
                        if (!metrics) return false;
                        
                        const daysSinceLastPurchase = metrics.lastPurchase
                          ? Math.floor((new Date() - new Date(metrics.lastPurchase)) / (1000 * 60 * 60 * 24))
                          : null;

                        switch (statusFilter) {
                          case 'active':
                            return daysSinceLastPurchase !== null && daysSinceLastPurchase <= 3;
                          case 'at_risk':
                            return daysSinceLastPurchase !== null && daysSinceLastPurchase > 3 && daysSinceLastPurchase <= 7;
                          case 'inactive':
                            return daysSinceLastPurchase === null || daysSinceLastPurchase > 7;
                          default:
                            return true;
                        }
                      })
                      .map(customer => {
                        const metrics = reportData.customerMetrics.get(customer.id);
                        if (!metrics) return null;

                        const daysSinceLastPurchase = metrics.lastPurchase
                          ? Math.floor((new Date().getTime() - new Date(metrics.lastPurchase).getTime()) / (1000 * 60 * 60 * 24))
                          : null;

                        return (
                          <tr key={customer.id} className="border-b hover:bg-purple-50/50 transition-colors">
                            <td className="p-4">
                              <div className="flex items-center gap-2">
                                {daysSinceLastPurchase === null ? '🔴' : 
                                 daysSinceLastPurchase <= 3 ? '🟢' :
                                 daysSinceLastPurchase <= 7 ? '🟡' : '🔴'}
                                <span className="text-sm text-gray-600">
                                  {daysSinceLastPurchase === null ? 'Inativo' :
                                   daysSinceLastPurchase <= 3 ? 'Ativo' :
                                   daysSinceLastPurchase <= 7 ? 'Em risco' : 'Inativo'}
                                </span>
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {customer.name || 'Não informado'}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="text-gray-600">
                                {customer.phone}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="text-gray-600">
                                {getLastActivity(customer, metrics)}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {metrics.totalPurchases}
                              </div>
                            </td>
                            <td className="p-4">
                              <div className="font-medium text-gray-900">
                                {formatCurrency(metrics.totalSpent)}
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                  </tbody>
                </table>
              </div>

              <div className="p-4 bg-gray-50 border-t">
                <div className="flex items-center gap-6 text-sm text-gray-600">
                  <div className="flex items-center gap-2">
                    <span>🟢</span>
                    <span>Última compra em até 3 dias</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span>🟡</span>
                    <span>Última compra entre 4 e 7 dias</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span>🔴</span>
                    <span>Última compra há mais de 8 dias</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="bg-white rounded-lg shadow-lg overflow-hidden">
            <div className="flex border-b bg-purple-50">
              <button
                className={`flex-1 px-6 py-4 text-sm font-medium transition-colors ${
                  activeTab === 'purchases' 
                    ? 'text-purple-900 border-b-2 border-purple-600 bg-white' 
                    : 'text-gray-600 hover:text-purple-600'
                }`}
                onClick={() => setActiveTab('purchases')}
              >
                <div className="flex items-center justify-center gap-2">
                  <ShoppingBag className="w-4 h-4" />
                  Compras
                </div>
              </button>
              <button
                className={`flex-1 px-6 py-4 text-sm font-medium transition-colors ${
                  activeTab === 'redemptions' 
                    ? 'text-purple-900 border-b-2 border-purple-600 bg-white' 
                    : 'text-gray-600 hover:text-purple-600'
                }`}
                onClick={() => setActiveTab('redemptions')}
              >
                <div className="flex items-center justify-center gap-2">
                  <Gift className="w-4 h-4" />
                  Resgates
                </div>
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="text-left border-b bg-gray-50">
                    <th className="p-4 text-sm font-medium text-gray-500">Data</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Cliente</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Loja</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Atendente</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Valor</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Status</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={7} className="p-4 text-center text-gray-500">
                        <div className="flex items-center justify-center gap-2">
                          <div className="w-5 h-5 border-2 border-purple-600 border-t-transparent rounded-full animate-spin" />
                          <span>Carregando...</span>
                        </div>
                      </td>
                    </tr>
                  ) : currentTransactions.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="p-4 text-center text-gray-500">
                        Nenhuma transação encontrada
                      </td>
                    </tr>
                  ) : (
                    currentTransactions
                      .filter(t => activeTab === 'purchases' ? t.type === 'purchase' : t.type === 'redemption')
                      .map((transaction) => (
                        <tr key={transaction.id} className="border-b hover:bg-purple-50/50 transition-colors">
                          <td className="p-4">
                            {formatDateTime(transaction.created_at)}
                          </td>
                          <td className="p-4">
                            <div className="font-medium text-gray-900">
                              {transaction.customers?.name || 'Não informado'}
                            </div>
                            <div className="text-sm text-gray-500">
                              {transaction.customers?.phone || 'N/A'}
                            </div>
                          </td>
                          <td className="p-4">
                            <div className="flex items-center gap-2">
                              <MapPin className="w-4 h-4 text-gray-400" />
                              <div className="text-gray-600">
                                {transaction.stores?.name || 'Loja não informada'}
                              </div>
                            </div>
                          </td>
                          <td className="p-4">
                            <div className="flex items-center gap-2">
                              <UserCircle className="w-4 h-4 text-gray-400" />
                              <div className="text-gray-600">
                                {transaction.attendant_name || 'Não informado'}
                              </div>
                            </div>
                          </td>
                          <td className="p-4">
                            <div className="font-medium text-gray-900">
                              {formatCurrency(transaction.amount)}
                            </div>
                            {transaction.type === 'purchase' && (
                              <div className="text-sm text-purple-600">
                                + {formatCurrency(transaction.cashback_amount)} cashback
                              </div>
                            )}
                          </td>
                          <td className="p-4">
                            <span className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-full text-sm font-medium ${
                              transaction.status === 'approved'
                                ? 'bg-green-50 text-green-700 border border-green-200'
                                : transaction.status === 'rejected'
                                ? 'bg-red-50 text-red-700 border border-red-200'
                                : 'bg-yellow-50 text-yellow-700 border border-yellow-200'
                            }`}>
                              {transaction.status === 'approved' 
                                ? <CheckCircle2 className="w-4 h-4" /> 
                                : transaction.status === 'rejected'
                                ? <XCircle className="w-4 h-4" />
                                : <Clock className="w-4 h-4" />
                              }
                              {transaction.status === 'approved' ? 'Aprovado' :
                               transaction.status === 'rejected' ? 'Rejeitado' : 'Pendente'}
                            </span>
                          </td>
                          <td className="p-4">
                            {transaction.status === 'pending' && (
                              <div className="flex gap-2">
                                <button
                                  onClick={() => handleStatusChange(transaction, 'approved')}
                                  className="p-1.5 text-green-600 hover:text-green-700 hover:bg-green-50 rounded-lg transition-colors"
                                  title="Aprovar"
                                >
                                  <CheckCircle2 className="w-5 h-5" />
                                </button>
                                <button
                                  onClick={() => handleStatusChange(transaction, 'rejected')}
                                  className="p-1.5 text-red-600 hover:text-red-700 hover:bg-red-50 rounded-lg transition-colors"
                                  title="Rejeitar"
                                >
                                  <XCircle className="w-5 h-5" />
                                </button>
                              </div>
                            )}
                          </td>
                        </tr>
                      ))
                  )}
                </tbody>
              </table>
            </div>

            {totalPages > 1 && (
              <div className="flex items-center justify-between px-4 py-3 bg-gray-50 border-t">
                <div className="flex items-center gap-2">
                  <button
                    onClick={handlePreviousPage}
                    disabled={currentPage === 1}
                    className="p-2 text-gray-600 hover:text-gray-900 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg hover:bg-gray-100 transition-colors"
                  >
                    <ChevronLeft className="w-5 h-5" />
                  </button>
                  <span className="text-sm text-gray-600">
                    Página {currentPage} de {totalPages}
                  </span>
                  <button
                    onClick={handleNextPage}
                    disabled={currentPage === totalPages}
                    className="p-2 text-gray-600 hover:text-gray-900 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg hover:bg-gray-100 transition-colors"
                  >
                    <ChevronRight className="w-5 h-5" />
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}