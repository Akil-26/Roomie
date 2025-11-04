// ignore_for_file: unnecessary_import, unused_local_variable

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:roomie/data/models/message_model.dart';

class CreatePollDialog extends StatefulWidget {
  const CreatePollDialog({super.key});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length < 10) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  void _createPoll() {
    if (_isCreating) return;

    try {
      setState(() {
        _isCreating = true;
      });

      final question = _questionController.text.trim();
      if (question.isEmpty) {
        _showError('Please enter a question');
        return;
      }

      final options =
          _optionControllers
              .map((controller) => controller.text.trim())
              .where((text) => text.isNotEmpty)
              .toList();

      if (options.length < 2) {
        _showError('Please enter at least 2 options');
        return;
      }

      final pollData = PollData(
        question: question,
        options:
            options
                .asMap()
                .entries
                .map(
                  (entry) =>
                      PollOption(id: 'option_${entry.key}', title: entry.value),
                )
                .toList(),
        allowMultiple: _allowMultiple,
        createdAt: DateTime.now(),
      );

      Navigator.of(context).pop(pollData);
    } catch (e) {
      debugPrint('Error creating poll: $e');
      _showError('Failed to create poll. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Dialog(
      insetPadding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 40,
        bottom: 0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(
          maxWidth: 400,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.poll, color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Create Poll',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Question input
              TextField(
                controller: _questionController,
                decoration: InputDecoration(
                  labelText: 'Poll Question',
                  hintText: 'What would you like to ask?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.help_outline),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),

              const SizedBox(height: 20),

              // Options
              Text(
                'Options',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              // Options list - no fixed height
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _optionControllers.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _optionControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Option ${index + 1}',
                              hintText: 'Enter option...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(
                                Icons.radio_button_unchecked,
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        if (_optionControllers.length > 2) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _removeOption(index),
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              // Add option button
              if (_optionControllers.length < 10)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Option'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              // Settings
              CheckboxListTile(
                title: const Text('Allow multiple selections'),
                subtitle: const Text('Users can select more than one option'),
                value: _allowMultiple,
                onChanged: (value) {
                  setState(() {
                    _allowMultiple = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createPoll,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Create Poll'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreateTodoDialog extends StatefulWidget {
  const CreateTodoDialog({super.key});

  @override
  State<CreateTodoDialog> createState() => _CreateTodoDialogState();
}

class _CreateTodoDialogState extends State<CreateTodoDialog> {
  final TextEditingController _titleController = TextEditingController();
  final List<TextEditingController> _taskControllers = [
    TextEditingController(),
  ];
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in _taskControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addTask() {
    if (_taskControllers.length < 20) {
      setState(() {
        _taskControllers.add(TextEditingController());
      });
    }
  }

  void _removeTask(int index) {
    if (_taskControllers.length > 1) {
      setState(() {
        _taskControllers[index].dispose();
        _taskControllers.removeAt(index);
      });
    }
  }

  void _createTodo() {
    if (_isCreating) return;

    try {
      setState(() {
        _isCreating = true;
      });

      final title = _titleController.text.trim();
      if (title.isEmpty) {
        _showError('Please enter a title');
        return;
      }

      final tasks =
          _taskControllers
              .map((controller) => controller.text.trim())
              .where((text) => text.isNotEmpty)
              .toList();

      if (tasks.isEmpty) {
        _showError('Please enter at least one task');
        return;
      }

      final todoData = TodoData(
        title: title,
        items:
            tasks
                .asMap()
                .entries
                .map(
                  (entry) =>
                      TodoItem(id: 'task_${entry.key}', title: entry.value),
                )
                .toList(),
      );

      Navigator.of(context).pop(todoData);
    } catch (e) {
      debugPrint('Error creating todo: $e');
      _showError('Failed to create to-do list. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Dialog(
      insetPadding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 40,
        bottom:0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(
          maxWidth: 400,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.task_alt, color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Create To-Do List',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Title input
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'List Title',
                  hintText: 'What needs to be done?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),

              const SizedBox(height: 20),

              // Tasks
              Text(
                'Tasks',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              // Tasks list - no fixed height
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _taskControllers.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _taskControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Task ${index + 1}',
                              hintText: 'Enter task...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(
                                Icons.check_box_outline_blank,
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        if (_taskControllers.length > 1) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _removeTask(index),
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              // Add task button
              if (_taskControllers.length < 20)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Task'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createTodo,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Create List'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
