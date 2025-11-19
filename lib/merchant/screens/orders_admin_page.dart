// lib/merchant/screens/orders_admin_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/branding/branding_providers.dart';
import '../../features/orders/data/order_models.dart' as om;
import '../../features/loyalty/data/loyalty_service.dart';

/// ===== Filters =====
enum OrdersFilter { all, pending, preparing, ready, served, cancelled }

extension OrdersFilterX on OrdersFilter {
  String? get statusString {
    switch (this) {
      case OrdersFilter.all:
        return null; // "All" excludes cancelled below
      case OrdersFilter.pending:
        return 'pending';
      case OrdersFilter.preparing:
        return 'preparing';
      case OrdersFilter.ready:
        return 'ready';
      case OrdersFilter.served:
        return 'served';
      case OrdersFilter.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case OrdersFilter.all:
        return 'All';
      case OrdersFilter.pending:
        return 'Pending';
      case OrdersFilter.preparing:
        return 'Preparing';
      case OrdersFilter.ready:
        return 'Ready';
      case OrdersFilter.served:
        return 'Served';
      case OrdersFilter.cancelled:
        return 'Cancelled';
    }
  }
}

final ordersFilterProvider =
    StateProvider<OrdersFilter>((_) => OrdersFilter.all);

/// ===== Date range for filtering =====
class DateRangeFilter {
  final DateTime start;
  final DateTime end;

  DateRangeFilter({required this.start, required this.end});

  // Today only (default)
  factory DateRangeFilter.today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return DateRangeFilter(start: start, end: end);
  }
}

final dateRangeFilterProvider =
    StateProvider<DateRangeFilter>((_) => DateRangeFilter.today());

/// ===== Lightweight admin models =====
class _AdminOrder {
  final String id;
  final String orderNo;
  final om.OrderStatus status;
  final DateTime createdAt;
  final List<_AdminItem> items;
  final double subtotal;
  final String? table;

  // Loyalty fields
  final String? customerPhone;
  final String? customerCarPlate;
  final double? loyaltyDiscount;
  final int? loyaltyPointsUsed;

  _AdminOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.subtotal,
    this.table,
    this.customerPhone,
    this.customerCarPlate,
    this.loyaltyDiscount,
    this.loyaltyPointsUsed,
  });
}

class _AdminItem {
  final String name;
  final double price;
  final int qty;
  final String? note;

  _AdminItem({
    required this.name,
    required this.price,
    required this.qty,
    this.note,
  });
}

/// ===== Orders stream (recent first) =====
final ordersStreamProvider =
    StreamProvider.autoDispose<List<_AdminOrder>>((ref) {
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);
  final dateRange = ref.watch(dateRangeFilterProvider);

  final col = FirebaseFirestore.instance
      .collection('merchants')
      .doc(m)
      .collection('branches')
      .doc(b)
      .collection('orders')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dateRange.start))
      .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(dateRange.end))
      .orderBy('createdAt', descending: true)
      .limit(200);

  return col.snapshots().map((qs) {
    return qs.docs.map((d) {
      final data = d.data();
      final ts = data['createdAt'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime.now();

      final rawItems = (data['items'] as List?) ?? const [];
      final items = rawItems.whereType<Map>().map((m) {
        final price = (m['price'] is num)
            ? (m['price'] as num).toDouble()
            : double.tryParse('${m['price']}') ?? 0.0;
        final qty = (m['qty'] is num)
            ? (m['qty'] as num).toInt()
            : int.tryParse('${m['qty']}') ?? 0;
        return _AdminItem(
          name: (m['name'] ?? '').toString(),
          price: price,
          qty: qty,
          note: (m['note'] as String?)?.trim(),
        );
      }).toList();

      final subtotal = (data['subtotal'] is num)
          ? (data['subtotal'] as num).toDouble()
          : double.tryParse('${data['subtotal']}') ?? 0.0;

      final loyaltyDiscount = data['loyaltyDiscount'] != null
          ? ((data['loyaltyDiscount'] is num)
              ? (data['loyaltyDiscount'] as num).toDouble()
              : double.tryParse('${data['loyaltyDiscount']}') ?? 0.0)
          : null;

      final loyaltyPointsUsed = data['loyaltyPointsUsed'] != null
          ? ((data['loyaltyPointsUsed'] is num)
              ? (data['loyaltyPointsUsed'] as num).toInt()
              : int.tryParse('${data['loyaltyPointsUsed']}') ?? 0)
          : null;

      return _AdminOrder(
        id: d.id,
        orderNo: (data['orderNo'] ?? '—').toString(),
        status: _statusFromString((data['status'] ?? 'pending').toString()),
        createdAt: dt,
        items: items,
        subtotal: double.parse(subtotal.toStringAsFixed(3)),
        table: (data['table'] as String?)?.trim(),
        customerPhone: (data['customerPhone'] as String?)?.trim(),
        customerCarPlate: (data['customerCarPlate'] as String?)?.trim(),
        loyaltyDiscount: loyaltyDiscount,
        loyaltyPointsUsed: loyaltyPointsUsed,
      );
    }).toList();
  });
});

/// ===== Status helpers =====
om.OrderStatus _statusFromString(String s) {
  switch (s) {
    case 'pending':
      return om.OrderStatus.pending;
    case 'accepted':
      return om.OrderStatus.accepted;
    case 'preparing':
      return om.OrderStatus.preparing;
    case 'ready':
      return om.OrderStatus.ready;
    case 'served':
      return om.OrderStatus.served;
    case 'cancelled':
      return om.OrderStatus.cancelled;
    default:
      return om.OrderStatus.pending;
  }
}

String _toFirestore(om.OrderStatus s) {
  switch (s) {
    case om.OrderStatus.pending:
      return 'pending';
    case om.OrderStatus.accepted:
      return 'accepted';
    case om.OrderStatus.preparing:
      return 'preparing';
    case om.OrderStatus.ready:
      return 'ready';
    case om.OrderStatus.served:
      return 'served';
    case om.OrderStatus.cancelled:
      return 'cancelled';
  }
}

String _label(om.OrderStatus s) {
  switch (s) {
    case om.OrderStatus.pending:
      return 'Pending';
    case om.OrderStatus.accepted:
      return 'Accepted';
    case om.OrderStatus.preparing:
      return 'Preparing';
    case om.OrderStatus.ready:
      return 'Ready';
    case om.OrderStatus.served:
      return 'Served';
    case om.OrderStatus.cancelled:
      return 'Cancelled';
  }
}

String _formatDateRange(DateRangeFilter range) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final rangeStart = DateTime(range.start.year, range.start.month, range.start.day);

  // Check if it's today only
  if (rangeStart.isAtSameMomentAs(today) &&
      range.start.day == range.end.day &&
      range.start.month == range.end.month &&
      range.start.year == range.end.year) {
    return 'Today';
  }

  // Format as date range
  return '${range.start.month}/${range.start.day} - ${range.end.month}/${range.end.day}';
}

/// ===== Page =====
class OrdersAdminPage extends ConsumerWidget {
  const OrdersAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersStreamProvider);
    final selected = ref.watch(ordersFilterProvider);
    final dateRange = ref.watch(dateRangeFilterProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        centerTitle: true,
        actions: [
          // Date range picker
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: _formatDateRange(dateRange),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: DateTimeRange(
                  start: dateRange.start,
                  end: dateRange.end,
                ),
                builder: (context, child) {
                  return Column(
                    children: [
                      Expanded(child: child!),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextButton.icon(
                          icon: const Icon(Icons.today),
                          label: const Text('Today Only'),
                          onPressed: () {
                            Navigator.pop(context, DateTimeRange(
                              start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                              end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
                            ));
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
              if (picked != null) {
                ref.read(dateRangeFilterProvider.notifier).state = DateRangeFilter(
                  start: DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0),
                  end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _FiltersRow(selected: selected),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load orders\n$e',
                      textAlign: TextAlign.center),
                ),
              ),
              data: (all) {
                // "All" excludes served and cancelled (only active orders)
                final f = selected.statusString;
                final list = (f == null)
                    ? all
                        .where((o) =>
                          o.status != om.OrderStatus.served &&
                          o.status != om.OrderStatus.cancelled
                        )
                        .toList()
                    : all.where((o) => _toFirestore(o.status) == f).toList();

                if (list.isEmpty) {
                  return Center(
                    child: Text('No orders',
                        style: TextStyle(color: onSurface.withOpacity(0.7))),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: onSurface.withOpacity(0.08)),
                  itemBuilder: (_, i) => _OrderTile(order: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ===== Filters row =====
class _FiltersRow extends ConsumerWidget {
  final OrdersFilter selected;
  const _FiltersRow({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget chip(OrdersFilter f) {
      final isSel = selected == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(f.label),
          selected: isSel,
          onSelected: (_) => ref.read(ordersFilterProvider.notifier).state = f,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          chip(OrdersFilter.all),
          chip(OrdersFilter.pending),
          chip(OrdersFilter.preparing),
          chip(OrdersFilter.ready),
          chip(OrdersFilter.served),
          chip(OrdersFilter.cancelled),
        ],
      ),
    );
  }
}

/// ===== Order tile =====
class _OrderTile extends ConsumerWidget {
  final _AdminOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final notesCount =
        order.items.where((it) => (it.note ?? '').trim().isNotEmpty).length;

    final finished = order.status == om.OrderStatus.served ||
                    order.status == om.OrderStatus.cancelled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: finished ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: finished
            ? onSurface.withOpacity(0.1)
            : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: () => _showItems(context, order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Order # + Car plate (PROMINENT) + Time + Status
              Row(
                children: [
                  // Order number (small font)
                  Text(
                    order.orderNo,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: onSurface.withOpacity(0.6),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Car plate - MOST IMPORTANT
                  if (order.customerCarPlate != null && order.customerCarPlate!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_car, size: 18, color: cs.onPrimary),
                          const SizedBox(width: 6),
                          Text(
                            order.customerCarPlate!,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: cs.onPrimary,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  // Time
                  Text(
                    _fmtTimeRelative(order.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status pill
                  _StatusPill(status: order.status),
                ],
              ),

              const SizedBox(height: 8),

              // Phone number
              if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.phone, size: 14, color: onSurface.withOpacity(0.6)),
                    const SizedBox(width: 4),
                    Text(
                      order.customerPhone!,
                      style: TextStyle(
                        fontSize: 13,
                        color: onSurface.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Order details row
              Row(
                children: [
                  // Items count
                  Icon(Icons.shopping_bag_outlined, size: 16, color: onSurface.withOpacity(0.6)),
                  const SizedBox(width: 4),
                  Text(
                    '${order.items.length} items',
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurface.withOpacity(0.8),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Notes indicator
                  if (notesCount > 0) ...[
                    Icon(Icons.note_alt_outlined, size: 16, color: onSurface.withOpacity(0.6)),
                    const SizedBox(width: 4),
                    Text(
                      '$notesCount note${notesCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: onSurface.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Loyalty discount indicator
                  if (order.loyaltyDiscount != null && order.loyaltyDiscount! > 0) ...[
                    Icon(Icons.loyalty, size: 16, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      '-${order.loyaltyDiscount!.toStringAsFixed(3)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.orange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  const Spacer(),

                  // Total amount
                  Text(
                    order.subtotal.toStringAsFixed(3),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),

              // Action buttons (if not finished)
              if (!finished) ...[
                const SizedBox(height: 8),
                _QuickActions(order: order),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTimeRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showItems(BuildContext context, _AdminOrder o) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Header: Order Number + Car Plate
                Row(
                  children: [
                    Text(
                      'Order ${o.orderNo}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    if (o.customerCarPlate != null && o.customerCarPlate!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions_car, size: 16, color: cs.onPrimary),
                            const SizedBox(width: 6),
                            Text(
                              o.customerCarPlate!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: cs.onPrimary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Customer Info Card
                Card(
                  color: cs.surfaceVariant.withOpacity(0.3),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customer Info',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (o.customerPhone != null && o.customerPhone!.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.phone, size: 16, color: onSurface.withOpacity(0.6)),
                              const SizedBox(width: 8),
                              Text(
                                o.customerPhone!,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        if (o.table != null && o.table!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.table_bar, size: 16, color: onSurface.withOpacity(0.6)),
                              const SizedBox(width: 8),
                              Text(
                                'Table ${o.table}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Order Items Header
                Row(
                  children: [
                    const Text(
                      'Order Items',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${o.items.length} items',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Items List
                ...o.items.map((it) {
                  final note = (it.note ?? '').trim();
                  final hasNote = note.isNotEmpty;
                  final lineTotal = it.price * it.qty;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: onSurface.withOpacity(0.1)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      it.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${it.price.toStringAsFixed(3)} × ${it.qty}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                lineTotal.toStringAsFixed(3),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          if (hasNote) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.amber.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.note_alt_outlined,
                                    size: 16,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Order Summary
                Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Subtotal',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          o.subtotal.toStringAsFixed(3),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (o.loyaltyDiscount != null && o.loyaltyDiscount! > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.loyalty, size: 16, color: Colors.orange),
                          const SizedBox(width: 6),
                          const Text(
                            'Loyalty Discount',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                          if (o.loyaltyPointsUsed != null && o.loyaltyPointsUsed! > 0)
                            Text(
                              ' (${o.loyaltyPointsUsed} pts)',
                              style: TextStyle(
                                fontSize: 12,
                                color: onSurface.withOpacity(0.6),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '-${o.loyaltyDiscount!.toStringAsFixed(3)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            (o.subtotal - (o.loyaltyDiscount ?? 0.0)).toStringAsFixed(3),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// ===== Status pill (with translucent “shadow” tints) =====
class _StatusPill extends StatelessWidget {
  final om.OrderStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    // Base neutral
    Color bg = onSurface.withOpacity(0.06);
    Color border = Colors.transparent;
    Color fg = onSurface;
    List<BoxShadow> shadow = const [];

    if (status == om.OrderStatus.served || status == om.OrderStatus.cancelled) {
      final bool served = status == om.OrderStatus.served;
      final Color tint = served
          ? const Color(0xFF22C55E) // green-500
          : const Color(0xFFEF4444);  // red-500

      bg = tint.withOpacity(served ? 0.16 : 0.12);
      border = tint.withOpacity(served ? 0.28 : 0.22);
      fg = onSurface.withOpacity(0.95);
      shadow = [
        BoxShadow(
          color: tint.withOpacity(0.16),
          blurRadius: 12,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
        boxShadow: shadow,
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// ===== Next action data =====
class _NextAction {
  final String label;
  final IconData icon;
  final Color color;

  _NextAction({
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// ===== Quick action buttons =====
class _QuickActions extends ConsumerStatefulWidget {
  final _AdminOrder order;
  const _QuickActions({required this.order});

  @override
  ConsumerState<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends ConsumerState<_QuickActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cur = widget.order.status;

    // Determine next action
    final nextAction = _getNextAction(cur);
    if (nextAction == null) return const SizedBox.shrink();

    return Row(
      children: [
        // Cancel button (small, subtle)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _setStatus(om.OrderStatus.cancelled),
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 8),
        // Main next action button (prominent)
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _busy ? null : () => _performNextAction(),
            icon: Icon(nextAction.icon, size: 20),
            label: Text(nextAction.label),
            style: ElevatedButton.styleFrom(
              backgroundColor: nextAction.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 2,
            ),
          ),
        ),
      ],
    );
  }

  _NextAction? _getNextAction(om.OrderStatus status) {
    switch (status) {
      case om.OrderStatus.pending:
        return _NextAction(
          label: 'Start Preparing',
          icon: Icons.restaurant,
          color: Colors.blue,
        );
      case om.OrderStatus.accepted:
        return _NextAction(
          label: 'Start Preparing',
          icon: Icons.restaurant,
          color: Colors.blue,
        );
      case om.OrderStatus.preparing:
        return _NextAction(
          label: 'Mark Ready',
          icon: Icons.done,
          color: Colors.orange,
        );
      case om.OrderStatus.ready:
        return _NextAction(
          label: 'Mark Served',
          icon: Icons.check_circle,
          color: Colors.green,
        );
      case om.OrderStatus.served:
      case om.OrderStatus.cancelled:
        return null;
    }
  }

  Future<void> _performNextAction() async {
    final cur = widget.order.status;
    switch (cur) {
      case om.OrderStatus.pending:
        await _acceptAndStartPreparing();
        break;
      case om.OrderStatus.accepted:
        await _setStatus(om.OrderStatus.preparing);
        break;
      case om.OrderStatus.preparing:
        await _setStatus(om.OrderStatus.ready);
        break;
      case om.OrderStatus.ready:
        await _setStatus(om.OrderStatus.served);
        break;
      case om.OrderStatus.served:
      case om.OrderStatus.cancelled:
        break;
    }
  }

  Future<void> _acceptAndStartPreparing() async {
    setState(() => _busy = true);
    final m = ref.read(merchantIdProvider);
    final b = ref.read(branchIdProvider);
    final doc = FirebaseFirestore.instance
        .collection('merchants')
        .doc(m)
        .collection('branches')
        .doc(b)
        .collection('orders')
        .doc(widget.order.id);

    try {
      await doc.update({
        'status': _toFirestore(om.OrderStatus.accepted),
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await doc.update({
        'status': _toFirestore(om.OrderStatus.preparing),
        'preparingAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(om.OrderStatus newStatus) async {
    final cur = widget.order.status;
    if (newStatus == om.OrderStatus.pending && cur != om.OrderStatus.pending) {
      return;
    }

    setState(() => _busy = true);
    final m = ref.read(merchantIdProvider);
    final b = ref.read(branchIdProvider);
    final doc = FirebaseFirestore.instance
        .collection('merchants')
        .doc(m)
        .collection('branches')
        .doc(b)
        .collection('orders')
        .doc(widget.order.id);

    try {
      final payload = <String, dynamic>{
        'status': _toFirestore(newStatus),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (newStatus) {
        case om.OrderStatus.preparing:
          payload['preparingAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.ready:
          payload['readyAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.served:
          payload['servedAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.cancelled:
          payload['cancelledAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.pending:
        case om.OrderStatus.accepted:
          break;
      }

      await doc.update(payload);

      // Award loyalty points when order is marked as served
      if (newStatus == om.OrderStatus.served) {
        final order = widget.order;
        if (order.customerPhone != null && order.customerPhone!.isNotEmpty &&
            order.customerCarPlate != null && order.customerCarPlate!.isNotEmpty) {
          try {
            final loyaltyService = ref.read(loyaltyServiceProvider);
            // Final amount = subtotal - discount
            final finalAmount = order.subtotal - (order.loyaltyDiscount ?? 0.0);

            await loyaltyService.awardPoints(
              phone: order.customerPhone!,
              carPlate: order.customerCarPlate!,
              orderAmount: finalAmount,
              orderId: order.id,
            );
          } catch (e) {
            debugPrint('[OrdersAdmin] Failed to award loyalty points: $e');
            // Don't block the status update if points awarding fails
          }
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
