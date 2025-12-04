// lib/features/orders/screens/order_status_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/data/order_models.dart';
import '../../orders/data/order_service.dart';

class OrderStatusPage extends ConsumerWidget {
  final String orderId;
  const OrderStatusPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(orderServiceProvider).watchOrder(orderId);
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<Order>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Order Status'),
              centerTitle: true,
              elevation: 0,
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
            ),
            body: snap.hasError
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Failed to load order.\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        }

        final order = snap.data!;
        final finished = order.status == OrderStatus.served ||
            order.status == OrderStatus.cancelled;

        return PopScope(
          canPop: false, // Prevent going back after confirming order
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Order Status'),
              centerTitle: true,
              elevation: 0,
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              leading: finished
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        // Navigate back to menu (pop to root)
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                    )
                  : null,
            ),
            body: _buildBody(context, order, cs, finished),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, Order order, ColorScheme cs, bool finished) {
    // Soft, theme-safe tints (very transparent)
    final servedBg = const Color(0xFF22C55E).withOpacity(0.12);
    final servedBorder = const Color(0xFF22C55E).withOpacity(0.22);
    final cancelBg = const Color(0xFFEF4444).withOpacity(0.12);
    final cancelBorder = const Color(0xFFEF4444).withOpacity(0.22);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large status icon
          _buildStatusIcon(order.status, cs),
          const SizedBox(height: 16),

          // Order number - large and prominent
          Text(
            order.orderNo,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: cs.onSurface, // Uses theme's secondary color
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),

          // Car plate - prominently displayed
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cs.onSurface.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.onSurface.withOpacity(0.3), width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car, color: cs.onSurface, size: 24),
                const SizedBox(width: 8),
                Text(
                  order.customerCarPlate ?? 'N/A',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface, // Uses theme's secondary color
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Status message
          _buildStatusMessage(order.status, cs, finished, cancelBg, cancelBorder, servedBg, servedBorder),
          const SizedBox(height: 24),

          // Status progress
          _StatusPills(status: order.status),
          const SizedBox(height: 24),

          // Order summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Order Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface, // Uses theme's secondary color
                      ),
                    ),
                    Text(
                      '${order.subtotal.toStringAsFixed(3)} BHD',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface, // Uses theme's secondary color
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Order items
                ...order.items.map((item) {
                  final note = (item.note ?? '').trim();
                  final hasNote = note.isNotEmpty;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'x${item.qty}',
                            style: TextStyle(
                              color: cs.onSurface, // Uses theme's secondary color
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (hasNote) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: cs.outline.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.note, size: 16, color: cs.onSurface),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: cs.onSurface.withOpacity(0.8),
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
                        const SizedBox(width: 8),
                        Text(
                          item.price.toStringAsFixed(3),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                // Phone number
                if (order.customerPhone != null) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 18, color: cs.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 8),
                      Text(
                        order.customerPhone!,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(OrderStatus status, ColorScheme cs) {
    IconData icon;
    Color color;

    switch (status) {
      case OrderStatus.pending:
      case OrderStatus.accepted:
        icon = Icons.receipt_long;
        color = Colors.orange;
        break;
      case OrderStatus.preparing:
        icon = Icons.restaurant;
        color = Colors.blue;
        break;
      case OrderStatus.ready:
        icon = Icons.notifications_active;
        color = Colors.green;
        break;
      case OrderStatus.served:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case OrderStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3), width: 3),
      ),
      child: Icon(icon, size: 64, color: color),
    );
  }

  Widget _buildStatusMessage(
    OrderStatus status,
    ColorScheme cs,
    bool finished,
    Color cancelBg,
    Color cancelBorder,
    Color servedBg,
    Color servedBorder,
  ) {
    String title;
    String message;
    Color bgColor;
    Color borderColor;

    if (status == OrderStatus.cancelled) {
      title = 'Order Cancelled';
      message = 'This order has been cancelled. Please contact the merchant if you have questions.';
      bgColor = cancelBg;
      borderColor = cancelBorder;
    } else if (status == OrderStatus.served) {
      title = 'Order Served!';
      message = 'Your order has been served. Enjoy your meal!';
      bgColor = servedBg;
      borderColor = servedBorder;
    } else if (status == OrderStatus.ready) {
      title = 'Order Ready!';
      message = 'Your order is ready for pickup. Please proceed to the counter.';
      bgColor = const Color(0xFF22C55E).withOpacity(0.12);
      borderColor = const Color(0xFF22C55E).withOpacity(0.22);
    } else if (status == OrderStatus.preparing) {
      title = 'Being Prepared';
      message = 'Your order is being prepared. We\'ll notify you when it\'s ready!';
      bgColor = Colors.blue.withOpacity(0.12);
      borderColor = Colors.blue.withOpacity(0.22);
    } else {
      title = 'Order Received';
      message = 'We\'ve received your order and will start preparing it soon.';
      bgColor = Colors.orange.withOpacity(0.12);
      borderColor = Colors.orange.withOpacity(0.22);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPills extends StatelessWidget {
  final OrderStatus status;
  const _StatusPills({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Customer-facing steps
    const steps = [
      OrderStatus.pending,
      OrderStatus.accepted,
      OrderStatus.preparing,
      OrderStatus.ready,
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: steps.map((s) {
        final active = _indexOf(status) >= _indexOf(s);
        final bg = active ? cs.primary : cs.surfaceVariant;
        final fg = active ? cs.onPrimary : cs.onSurface;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            _label(s),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        );
      }).toList(),
    );
  }

  int _indexOf(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return 0;
      case OrderStatus.accepted:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.ready:
        return 3;
      case OrderStatus.served:
        return 4;
      case OrderStatus.cancelled:
        return 5;
    }
  }

  String _label(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.served:
        return 'Served';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}
