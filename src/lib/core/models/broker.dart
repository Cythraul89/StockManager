import 'package:equatable/equatable.dart';

class Broker extends Equatable {
  const Broker({
    required this.id,
    required this.name,
    this.notes,
  });

  final String id;
  final String name;
  final String? notes;

  Broker copyWith({String? id, String? name, String? notes}) => Broker(
        id: id ?? this.id,
        name: name ?? this.name,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props => [id, name, notes];
}
