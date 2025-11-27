import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/analytics_models.dart';
import '../data/analytics_service.dart';
import '../widgets/stat_card.dart';
import '../widgets/revenue_chart.dart';
import '../widgets/hourly_chart.dart';
import '../widgets/top_products_list.dart';
import '../widgets/category_breakdown_chart.dart';
import '../widgets/customer_insights_card.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/email_service.dart';

/// State provider for selected date range
final selectedDateRangeProvider = StateProvider<DateRange>((ref) => DateRange.last7Days);

/// Main analytics dashboard page for merchants
class AnalyticsDashboardPage extends ConsumerWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRange = ref.watch(selectedDateRangeProvider);
    final analyticsAsync = ref.watch(analyticsDashboardProvider(selectedRange));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        actions: [
          analyticsAsync.maybeWhen(
            data: (dashboard) => IconButton(
              icon: const Icon(Icons.email_outlined),
              tooltip: 'Email Report',
              onPressed: () => _showEmailReportDialog(context, ref, dashboard),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _DateRangeSelector(
            selectedRange: selectedRange,
            onRangeChanged: (range) {
              ref.read(selectedDateRangeProvider.notifier).state = range;
            },
          ),
        ),
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading analytics: $err'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(analyticsDashboardProvider(selectedRange)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (dashboard) => _buildDashboard(context, dashboard),
      ),
    );
  }

  Future<void> _showEmailReportDialog(
    BuildContext context,
    WidgetRef ref,
    AnalyticsDashboard dashboard,
  ) async {
    // Get merchant email from settings
    final merchantId = ref.read(merchantIdProvider);
    final branchId = ref.read(branchIdProvider);

    final settingsDoc = await FirebaseFirestore.instance
        .doc('merchants/$merchantId/branches/$branchId/config/settings')
        .get();

    final email = settingsDoc.data()?['emailNotifications']?['email'] as String?;

    if (email == null || email.isEmpty) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error_outline, color: Colors.orange, size: 48),
            title: const Text('Email Not Configured'),
            content: const Text(
              'Please configure your email address in Settings before generating reports.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => _EmailReportDialog(
          email: email,
          dashboard: dashboard,
          merchantId: merchantId,
          branchId: branchId,
        ),
      );
    }
  }

  Widget _buildDashboard(BuildContext context, AnalyticsDashboard dashboard) {
    if (dashboard.sales.totalOrders == 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No data for this period',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Orders will appear here once customers start ordering',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key metrics overview
          _SectionHeader(
            title: 'Sales Overview',
            subtitle: _formatDateRange(dashboard.startDate, dashboard.endDate),
          ),
          const SizedBox(height: 16),
          _buildKeyMetrics(dashboard.sales),
          const SizedBox(height: 32),

          // Revenue trend
          const _SectionHeader(title: 'Revenue Trend'),
          const SizedBox(height: 16),
          RevenueChart(trends: dashboard.dailyTrends),
          const SizedBox(height: 32),

          // Hourly distribution
          const _SectionHeader(title: 'Peak Hours'),
          const SizedBox(height: 16),
          HourlyChart(distribution: dashboard.hourlyDistribution),
          const SizedBox(height: 32),

          // Customer insights
          const _SectionHeader(title: 'Customer Insights'),
          const SizedBox(height: 16),
          CustomerInsightsCard(insights: dashboard.customerInsights),
          const SizedBox(height: 32),

          // Product performance
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(title: 'Top Selling Products'),
                    const SizedBox(height: 16),
                    TopProductsList(
                      products: dashboard.topProducts,
                      title: 'Best Sellers',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(title: 'Slow Moving Products'),
                    const SizedBox(height: 16),
                    TopProductsList(
                      products: dashboard.slowMovingProducts,
                      title: 'Need Attention',
                      isSlowMoving: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Category breakdown
          const _SectionHeader(title: 'Category Performance'),
          const SizedBox(height: 16),
          CategoryBreakdownChart(categories: dashboard.categoryPerformance),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildKeyMetrics(SalesAnalytics sales) {
    final currencyFormat = NumberFormat.currency(symbol: 'BHD ', decimalDigits: 3);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        StatCard(
          title: 'Total Revenue',
          value: currencyFormat.format(sales.totalRevenue),
          icon: Icons.monetization_on,
          color: Colors.green,
        ),
        StatCard(
          title: 'Total Orders',
          value: sales.totalOrders.toString(),
          icon: Icons.shopping_bag,
          color: Colors.blue,
        ),
        StatCard(
          title: 'Average Order Value',
          value: currencyFormat.format(sales.averageOrderValue),
          icon: Icons.attach_money,
          color: Colors.orange,
        ),
        StatCard(
          title: 'Completion Rate',
          value: '${sales.completionRate}%',
          subtitle: '${sales.completedOrders} completed, ${sales.cancelledOrders} cancelled',
          icon: Icons.check_circle,
          color: Colors.purple,
        ),
        StatCard(
          title: 'Total Items Sold',
          value: sales.totalItems.toString(),
          icon: Icons.inventory,
          color: Colors.teal,
        ),
      ],
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final dateFormat = DateFormat('MMM d, yyyy');
    return '${dateFormat.format(start)} - ${dateFormat.format(end)}';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ],
      ],
    );
  }
}

class _DateRangeSelector extends StatelessWidget {
  final DateRange selectedRange;
  final ValueChanged<DateRange> onRangeChanged;

  const _DateRangeSelector({
    required this.selectedRange,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: DateRange.values.where((r) => r != DateRange.custom).map((range) {
            final isSelected = range == selectedRange;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(range.label),
                selected: isSelected,
                onSelected: (_) => onRangeChanged(range),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _EmailReportDialog extends StatefulWidget {
  final String email;
  final AnalyticsDashboard dashboard;
  final String merchantId;
  final String branchId;

  const _EmailReportDialog({
    required this.email,
    required this.dashboard,
    required this.merchantId,
    required this.branchId,
  });

  @override
  State<_EmailReportDialog> createState() => _EmailReportDialogState();
}

class _EmailReportDialogState extends State<_EmailReportDialog> {
  bool _isSending = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy');
    final dateRange = '${dateFormat.format(widget.dashboard.startDate)} - ${dateFormat.format(widget.dashboard.endDate)}';

    return AlertDialog(
      icon: const Icon(Icons.email, size: 48, color: Colors.blue),
      title: const Text('Email Sales Report'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send a detailed sales report for the selected period to your email.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.email_outlined, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Email:',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.date_range, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Period:',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateRange,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSending ? null : _sendReport,
          icon: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send),
          label: Text(_isSending ? 'Sending...' : 'Send Report'),
        ),
      ],
    );
  }

  Future<void> _sendReport() async {
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      // Get merchant name from branding
      final brandingDoc = await FirebaseFirestore.instance
          .doc('merchants/${widget.merchantId}/branches/${widget.branchId}/config/branding')
          .get();
      final merchantName = brandingDoc.data()?['title'] as String? ?? 'Your Store';

      // Prepare report data
      final sales = widget.dashboard.sales;
      final dateFormat = DateFormat('M/d/yyyy');
      final dateRange =
          '${dateFormat.format(widget.dashboard.startDate)} - ${dateFormat.format(widget.dashboard.endDate)}';

      // Get top items
      final topItems = widget.dashboard.topProducts.take(10).map((product) {
        return TopItem(
          name: product.name,
          count: product.orderCount,
          revenue: product.revenue,
        );
      }).toList();

      // Calculate orders by status
      final ordersByStatus = [
        StatusCount(status: 'completed', count: sales.completedOrders),
        StatusCount(status: 'cancelled', count: sales.cancelledOrders),
        StatusCount(status: 'pending', count: sales.totalOrders - sales.completedOrders - sales.cancelledOrders),
      ].where((s) => s.count > 0).toList();

      // Send email
      final result = await EmailService.sendReport(
        merchantName: merchantName,
        dateRange: dateRange,
        totalOrders: sales.totalOrders,
        totalRevenue: sales.totalRevenue,
        servedOrders: sales.completedOrders,
        cancelledOrders: sales.cancelledOrders,
        averageOrder: sales.averageOrderValue,
        topItems: topItems,
        ordersByStatus: ordersByStatus,
        toEmail: widget.email,
      );

      if (mounted) {
        if (result.success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Report sent to ${widget.email}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Failed to send email';
            _isSending = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isSending = false;
        });
      }
    }
  }
}
