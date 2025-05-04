import React, { useState, useEffect } from 'react';
import { ChevronLeft, ChevronRight, ShoppingBag, Gift, CheckCircle2, XCircle, Users, TrendingUp, Wallet, Clock, AlertTriangle, FileText, Lock } from 'lucide-react';
import DateRangeFilter from '../../components/DateRangeFilter';
import { supabase } from '../../lib/supabase';
import toast from 'react-hot-toast';
import { generateCustomerReport } from '../../utils/reportGenerator';

export default function Dashboard() {
  const [activeTab, setActiveTab] = useState('transactions');
  const [dateRange, setDateRange] = useState('today');
  const [customStartDate, setCustomStartDate] = useState(new Date());
  const [customEndDate, setCustomEndDate] = useState(new Date());
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [loading, setLoading] = useState(false);
  const [currentTransactions, setCurrentTransactions] = useState([]);
  const [reportData, setReportData] = useState(null);
  const [showAdvancedReport, setShowAdvancedReport] = useState(false);
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

      // Load transactions
      const { data: transactions, error: transactionsError } = await supabase
        .from('transactions')
        .select(`
          *,
          customers (
            id,
            name,
            phone,
            balance
          )
        `)
        .gte('created_at', startDate.toISOString())
        .lte('created_at', endDate.toISOString())
        .order('created_at', { ascending: false });

      if (transactionsError) throw transactionsError;

      // Load all customers for the period
      const { data: customers, error: customersError } = await supabase
        .from('customers')
        .select('*');

      if (customersError) throw customersError;

      // Calculate metrics
      const approvedPurchases = transactions.filter(t => t.type === 'purchase' && t.status === 'approved');
      const approvedRedemptions = transactions.filter(t => t.type === 'redemption' && t.status === 'approved');

      const totalRevenue = approvedPurchases.reduce((sum, t) => sum + Number(t.amount), 0);
      const totalCashback = approvedPurchases.reduce((sum, t) => sum + Number(t.cashback_amount), 0);
      const totalRedemptions = approvedRedemptions.reduce((sum, t) => sum + Number(t.amount), 0);

      // Calculate customer metrics
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

        // Determine customer status
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

      // Calculate overall metrics
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

      setCurrentTransactions(transactions);
      setTotalPages(Math.ceil(transactions.length / 10));

    } catch (error) {
      console.error('Error loading transactions:', error);
      toast.error('Erro ao carregar transações: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = async (transactionId, newStatus) => {
    try {
      const { error } = await supabase
        .from('transactions')
        .update({ status: newStatus })
        .eq('id', transactionId);

      if (error) throw error;

      toast.success('Status atualizado com sucesso!');
      loadTransactions();
    } catch (error) {
      console.error('Error updating status:', error);
      toast.error('Erro ao atualizar status: ' + error.message);
    }
  };

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

  const getStatusBadgeClass = (status) => {
    switch (status) {
      case 'approved':
        return 'bg-green-50 text-green-700 border border-green-200';
      case 'pending':
        return 'bg-yellow-50 text-yellow-700 border border-yellow-200';
      case 'rejected':
        return 'bg-red-50 text-red-700 border border-red-200';
      default:
        return 'bg-gray-50 text-gray-700 border border-gray-200';
    }
  };

  const getStatusIndicator = (status) => {
    switch (status) {
      case 'active':
        return (
          <div className="w-3 h-3 rounded-full bg-green-500" title="Cliente ativo" />
        );
      case 'at_risk':
        return (
          <div className="w-3 h-3 rounded-full bg-yellow-500" title="Em risco" />
        );
      default:
        return (
          <div className="w-3 h-3 rounded-full bg-red-500" title="Inativo" />
        );
    }
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

  const handleGeneratePDF = async () => {
    try {
      if (!reportData?.customers) {
        toast.error('Nenhum dado disponível para gerar relatório');
        return;
      }

      await generateCustomerReport(
        reportData.customers,
        { startDate: customStartDate, endDate: customEndDate },
        'profile'
      );

      toast.success('Relatório gerado com sucesso!');
    } catch (error) {
      console.error('Error generating report:', error);
      toast.error('Erro ao gerar relatório: ' + error.message);
    }
  };

  useEffect(() => {
    loadTransactions();
  }, [dateRange, activeTab]);

  return (
    <div className="p-6">
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <DateRangeFilter
            dateRange={dateRange}
            setDateRange={setDateRange}
            customStartDate={customStartDate}
            setCustomStartDate={setCustomStartDate}
            customEndDate={customEndDate}
            setCustomEndDate={setCustomEndDate}
            onGeneratePDF={handleGeneratePDF}
            onDateChange={loadTransactions}
          />
          <button
            onClick={() => setShowAdvancedReport(!showAdvancedReport)}
            className="btn-primary py-2 px-4 text-sm flex items-center gap-2"
          >
            <FileText className="w-4 h-4" />
            {showAdvancedReport ? 'Ocultar Relatório Avançado' : 'Relatório Avançado'}
          </button>
        </div>

        {showAdvancedReport ? (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              {/* Customers Card */}
              <div className="bg-white rounded-lg shadow p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Users className="w-5 h-5 text-purple-600" />
                    <h3 className="font-medium text-gray-900">Clientes</h3>
                  </div>
                  <span className="text-2xl font-bold text-gray-900">{metrics.totalCustomers}</span>
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-600">Ativos</span>
                    <span className="font-medium text-green-600">{metrics.activeCustomers}</span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-600">Em risco</span>
                    <span className="font-medium text-yellow-600">{metrics.atRiskCustomers}</span>
                  </div>
                </div>
              </div>

              {/* Revenue Card */}
              <div className="bg-white rounded-lg shadow p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <TrendingUp className="w-5 h-5 text-purple-600" />
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

              {/* Cashback Card */}
              <div className="bg-white rounded-lg shadow p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Wallet className="w-5 h-5 text-purple-600" />
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

              {/* At Risk Card */}
              <div className="bg-white rounded-lg shadow p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <AlertTriangle className="w-5 h-5 text-purple-600" />
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

            <div className="bg-white rounded-lg shadow overflow-hidden">
              <div className="p-4 border-b flex items-center justify-between">
                <h2 className="text-lg font-medium text-gray-900 flex items-center gap-2">
                  <FileText className="w-5 h-5 text-purple-600" />
                  Perfil de Compra dos Clientes
                </h2>
                <button
                  onClick={handleGeneratePDF}
                  className="btn-secondary py-2 px-4 text-sm flex items-center gap-2"
                >
                  <FileText className="w-4 h-4" />
                  Exportar PDF
                </button>
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
                      .map(customer => {
                        const metrics = reportData.customerMetrics.get(customer.id);
                        if (!metrics) return null;

                        const averageTicket = metrics.totalPurchases > 0 
                          ? metrics.totalSpent / metrics.totalPurchases 
                          : 0;

                        return (
                          <tr key={customer.id} className="border-b hover:bg-gray-50">
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

            <div className="bg-white rounded-lg shadow overflow-hidden">
              <div className="p-4 border-b">
                <h2 className="text-lg font-medium text-gray-900">
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
                      .map(customer => {
                        const metrics = reportData.customerMetrics.get(customer.id);
                        if (!metrics) return null;

                        return (
                          <tr key={customer.id} className="border-b">
                            <td className="p-4">
                              <div className="flex items-center">
                                {getStatusIndicator(metrics.status)}
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
            </div>
          </>
        ) : (
          <div className="bg-white rounded-lg shadow overflow-hidden">
            <div className="flex border-b">
              <button
                className={`flex-1 px-4 py-3 text-sm font-medium ${
                  activeTab === 'purchases' ? 'text-purple-600 border-b-2 border-purple-600' : 'text-gray-500'
                }`}
                onClick={() => setActiveTab('purchases')}
              >
                <div className="flex items-center justify-center gap-2">
                  <ShoppingBag className="w-4 h-4" />
                  Compras
                </div>
              </button>
              <button
                className={`flex-1 px-4 py-3 text-sm font-medium ${
                  activeTab === 'redemptions' ? 'text-purple-600 border-b-2 border-purple-600' : 'text-gray-500'
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
                    <th className="p-4 text-sm font-medium text-gray-500">Valor</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Status</th>
                    <th className="p-4 text-sm font-medium text-gray-500">Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={5} className="p-4 text-center text-gray-500">
                        Carregando...
                      </td>
                    </tr>
                  ) : currentTransactions.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="p-4 text-center text-gray-500">
                        Nenhuma transação encontrada
                      </td>
                    </tr>
                  ) : (
                    currentTransactions
                      .filter(t => activeTab === 'purchases' ? t.type === 'purchase' : t.type === 'redemption')
                      .map((transaction) => (
                        <tr key={transaction.id} className="border-b">
                          <td className="p-4">
                            {formatDateTime(transaction.created_at)}
                          </td>
                          <td className="p-4">
                            {transaction.customers?.name || transaction.customers?.phone || 'N/A'}
                          </td>
                          <td className="p-4">
                            {formatCurrency(transaction.amount)}
                          </td>
                          <td className="p-4">
                            <span className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusBadgeClass(transaction.status)}`}>
                              {transaction.status === 'approved' ? 'Aprovado' :
                               transaction.status === 'rejected' ? 'Rejeitado' : 'Pendente'}
                            </span>
                          </td>
                          <td className="p-4">
                            {transaction.status === 'pending' && (
                              <div className="flex gap-2">
                                <button
                                  onClick={() => handleStatusChange(transaction.id, 'approved')}
                                  className="text-green-600 hover:text-green-700"
                                >
                                  <CheckCircle2 className="w-5 h-5" />
                                </button>
                                <button
                                  onClick={() => handleStatusChange(transaction.id, 'rejected')}
                                  className="text-red-600 hover:text-red-700"
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
                    className="p-2 text-gray-600 hover:text-gray-900 disabled:opacity-50"
                  >
                    <ChevronLeft className="w-5 h-5" />
                  </button>
                  <span className="text-sm text-gray-600">
                    Página {currentPage} de {totalPages}
                  </span>
                  <button
                    onClick={handleNextPage}
                    disabled={currentPage === totalPages}
                    className="p-2 text-gray-600 hover:text-gray-900 disabled:opacity-50"
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