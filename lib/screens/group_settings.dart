import 'dart:io';
import 'package:flutter/material.dart';
import 'package:s_chat/models/chat_item.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/utils/app_alerts.dart';
import 'package:s_chat/widgets/chat/cached_media_image.dart';
import 'package:s_chat/widgets/user/user_image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({
    super.key,
    required this.group,
  });

  final ChatItem group;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late TextEditingController _nameController;
  late bool _isPrivate;
  File? _pickedGroupImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _isPrivate = widget.group.isPrivate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);

    // Validate unique group name before saving
    final isTaken = await MessageRepository.instance.isGroupNameTaken(
      newName,
      excludeGroupId: widget.group.id,
    );
    if (isTaken) {
      setState(() => _isSaving = false);
      if (mounted) {
        AppAlerts.showSnackBar(
          context,
          'A group named "$newName" already exists. Please choose a different name.',
          isError: true,
        );
      }
      return;
    }

    String imageUrl = widget.group.avatarUrl;
    if (_pickedGroupImage != null) {
      imageUrl = await MessageRepository.instance.uploadGroupImage(
        _pickedGroupImage!,
        widget.group.id,
      );
    }

    final updated = await MessageRepository.instance.updateGroupSettings(
      groupId: widget.group.id,
      newName: newName,
      newImageUrl: imageUrl,
    );

    if (mounted) {
      final finalGroup = (updated ?? widget.group).copyWith(
        name: newName,
        avatarUrl: imageUrl,
        isPrivate: _isPrivate,
      );
      Navigator.pop(context, finalGroup);
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await AppAlerts.showConfirmDialog(
      context,
      title: 'Delete Group?',
      content:
          'Are you sure you want to permanently delete "${widget.group.name}"? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      await MessageRepository.instance.deleteGroup(groupId: widget.group.id);
      if (mounted) {
        Navigator.pop(context, 'deleted');
      }
    }
  }

  Future<void> _showAddUsersDialog() async {
    final searchController = TextEditingController();
    final availableChats = await MessageRepository.instance.fetchAvailableChats();
    final candidateUsers = availableChats.where((c) => !c.isGroup).toList();
    final selectedUserIds = <String>{};

    if (!mounted) return;

    final added = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filter = searchController.text.trim().toLowerCase();
            final filteredCandidates = filter.isEmpty
                ? candidateUsers
                : candidateUsers
                    .where((u) => u.name.toLowerCase().contains(filter))
                    .toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.person_add_rounded, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add Members to ${widget.group.name}',
                      style: const TextStyle(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search users...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: filteredCandidates.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No users found'),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredCandidates.length,
                              itemBuilder: (context, index) {
                                final user = filteredCandidates[index];
                                final isSelected =
                                    selectedUserIds.contains(user.id);
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(user.name),
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedUserIds.add(user.id);
                                      } else {
                                        selectedUserIds.remove(user.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedUserIds.isEmpty
                      ? null
                      : () => Navigator.pop(context, true),
                  child: Text('Add (${selectedUserIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (added == true && selectedUserIds.isNotEmpty && mounted) {
      await MessageRepository.instance.addUsersToGroup(
        groupId: widget.group.id,
        userIds: selectedUserIds.toList(),
      );
      if (mounted) {
        AppAlerts.showSnackBar(
          context,
          'Added ${selectedUserIds.length} members',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final bool isOwner = widget.group.ownerId.isEmpty ||
        widget.group.isOwner(currentUserId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info & Settings'),
        actions: [
          if (isOwner)
            IconButton(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Avatar picker
            if (isOwner)
              UserImagePicker(
                onSelectImage: (image) {
                  _pickedGroupImage = image;
                },
              )
            else
              CircleAvatar(
                radius: 52,
                backgroundColor: colorScheme.primaryContainer,
                child: widget.group.avatarUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(52),
                        child: CachedMediaImage(
                          imageUrl: widget.group.avatarUrl,
                          width: 104,
                          height: 104,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Text(
                        widget.group.name.isNotEmpty
                            ? widget.group.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
              ),

            const SizedBox(height: 24),

            // Group Name field
            TextField(
              controller: _nameController,
              enabled: isOwner,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                prefixIcon: Icon(Icons.groups_rounded),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // Group Privacy Switch
            if (isOwner)
              SwitchListTile(
                value: _isPrivate,
                onChanged: (val) => setState(() => _isPrivate = val),
                title: const Text('Private Group'),
                subtitle: const Text(
                  'Only invited members can view messages in private groups',
                ),
                secondary: Icon(
                  _isPrivate
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  color: Colors.teal,
                ),
              ),

            const Divider(height: 32),

            // Add Members action
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.person_add_rounded, color: Colors.teal),
                title: const Text('Add Members'),
                onTap: _showAddUsersDialog,
              ),

            const SizedBox(height: 24),

            if (isOwner) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Group Settings'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  onPressed: _deleteGroup,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Delete Group'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
