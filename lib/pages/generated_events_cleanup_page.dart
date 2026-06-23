import 'package:flutter/material.dart';

import '../services/calendar_import_metadata.dart';
import '../services/calendar_sync_service.dart';

class GeneratedEventsCleanupPage extends StatefulWidget {
  const GeneratedEventsCleanupPage({
    super.key,
    required this.calendarSyncService,
  });

  final CalendarSyncService calendarSyncService;

  @override
  State<GeneratedEventsCleanupPage> createState() =>
      _GeneratedEventsCleanupPageState();
}

class _GeneratedEventsCleanupPageState
    extends State<GeneratedEventsCleanupPage> {
  var _loading = true;
  var _deleting = false;
  String? _error;
  List<GeneratedEventsGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups =
          await widget.calendarSyncService.scanGeneratedEventGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _groups = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteGroup(GeneratedEventsGroup group) async {
    final confirmed = await _confirm(
      title: '确认删除',
      message: '将删除 ${group.label} 中的 ${group.count} 条本软件生成日程。',
    );
    if (!confirmed) return;

    await _deleteGroups(
      [group],
      deleteOneGroup: true,
    );
  }

  Future<void> _deleteAll() async {
    final total = _groups.fold<int>(0, (sum, group) => sum + group.count);
    final confirmed = await _confirm(
      title: '确认全部删除',
      message: '将删除扫描到的全部 $total 条本软件生成日程。',
    );
    if (!confirmed) return;

    await _deleteGroups(_groups);
  }

  Future<void> _deleteGroups(
    List<GeneratedEventsGroup> groups, {
    bool deleteOneGroup = false,
  }) async {
    setState(() {
      _deleting = true;
    });

    try {
      final deleted = deleteOneGroup && groups.length == 1
          ? await widget.calendarSyncService.deleteGeneratedEventGroup(
              groups.single,
            )
          : await widget.calendarSyncService.deleteGeneratedEventGroups(groups);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $deleted 条本软件生成日程。')),
      );
      await _scan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('删除本软件生成的日程')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildGroups(),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroups() {
    if (_groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('没有扫描到本软件生成的日程。')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final group in _groups) ...[
          Card(
            child: ListTile(
              title: Text(group.label),
              subtitle: Text('${group.count} 条日程'),
              trailing: OutlinedButton(
                onPressed: _deleting ? null : () => _deleteGroup(group),
                child: const Text('删除'),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _deleting ? null : _deleteAll,
          icon: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever),
          label: const Text('全部删除'),
        ),
      ],
    );
  }
}
