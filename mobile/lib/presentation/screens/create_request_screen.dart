import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/enums.dart';
import '../../domain/validators.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key, this.initialServiceId});

  final String? initialServiceId;

  @override
  ConsumerState<CreateRequestScreen> createState() =>
      _CreateRequestScreenState();
}

class _CreateRequestScreenState extends ConsumerState<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _address = TextEditingController();

  String? _serviceId;
  RequestPriority _priority = RequestPriority.medium;
  DateTime? _preferredAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _serviceId = widget.initialServiceId;
  }

  @override
  void dispose() {
    _description.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _preferredAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _preferredAt ?? now.add(const Duration(days: 1))),
    );
    if (time == null) return;
    setState(() {
      _preferredAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_serviceId == null) {
      showErrorSnack(context, 'Please choose a service.');
      return;
    }
    if (_preferredAt == null) {
      showErrorSnack(context, 'Please pick a preferred date and time.');
      return;
    }

    setState(() => _busy = true);
    try {
      final created = await ref.read(requestRepositoryProvider).create(
            serviceId: _serviceId!,
            description: _description.text,
            preferredAt: _preferredAt!,
            address: _address.text,
            priority: _priority,
          );
      ref.invalidate(requestsProvider);
      if (mounted) {
        showInfoSnack(context, 'Request ${created.requestId} created');
        context.go('/requests/${created.id}');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create request')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              servicesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => const Text('Could not load services.'),
                data: (services) => DropdownButtonFormField<String>(
                  initialValue: _serviceId,
                  decoration: const InputDecoration(
                    labelText: 'Service type *',
                    prefixIcon: Icon(Icons.grid_view_outlined),
                  ),
                  items: [
                    for (final s in services)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _serviceId = v),
                  validator: (v) => v == null ? 'Choose a service' : null,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 4,
                minLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Describe the problem…',
                  alignLabelWithHint: true,
                ),
                validator: Validators.description,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  hintText: 'Flat / street / city / pincode',
                ),
                validator: Validators.address,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Preferred date & time *',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    _preferredAt == null
                        ? 'Select date and time'
                        : DateFormat('EEE, d MMM yyyy • h:mm a')
                            .format(_preferredAt!),
                    style: _preferredAt == null
                        ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).hintColor,
                            )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Priority', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<RequestPriority>(
                segments: [
                  for (final p in RequestPriority.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Submit request'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
