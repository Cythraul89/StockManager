import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/broker.dart';

class BrokerTile extends StatelessWidget {
  const BrokerTile({super.key, required this.broker});

  final Broker broker;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.account_balance)),
        title: Text(broker.name),
        subtitle: broker.notes != null && broker.notes!.isNotEmpty
            ? Text(broker.notes!, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/brokers/${broker.id}/edit'),
      ),
    );
  }
}
