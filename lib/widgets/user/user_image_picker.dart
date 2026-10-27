import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:s_chat/services/media_compression_service.dart';

class UserImagePicker extends StatefulWidget {
  const UserImagePicker({super.key, required this.onSelectImage});

  final void Function(File image) onSelectImage;

  @override
  State<UserImagePicker> createState() => _UserImagePickerState();
}


class _UserImagePickerState extends State<UserImagePicker> {
  File? _pickedImage;
  Uint8List? _pickedImageBytes; // web preview

  void _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;

    if (kIsWeb) {
      // On web, dart:io File is unavailable — read bytes directly.
      final bytes = await image.readAsBytes();
      setState(() => _pickedImageBytes = bytes);
      // Compression is a no-op on web; pass a dummy File path.
      // The caller must handle kIsWeb by reading bytes separately if needed.
      return;
    }

    final rawFile = File(image.path);
    final compressedFile = await MediaCompressionService.instance
        .compressImageFile(inputFile: rawFile);

    setState(() {
      _pickedImage = compressedFile;
      _pickedImageBytes = null;
    });
    widget.onSelectImage(compressedFile);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _pickImage(ImageSource.camera),
          child: Stack(
            children: [
              CircleAvatar(
                radius: 52,
                backgroundColor:
                    Theme.of(context).colorScheme.secondary.withAlpha(100),
                foregroundImage: _pickedImageBytes != null
                    ? MemoryImage(_pickedImageBytes!) as ImageProvider
                    : _pickedImage != null
                    ? FileImage(_pickedImage!)
                    : null,
                child: const Icon(Icons.camera_alt),
              ),
              if (_pickedImage != null || _pickedImageBytes != null)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withGreen(220),
                      borderRadius: BorderRadius.circular(200),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.image),
          label: Text(
            'Select image',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontFamily: 'Audiowide',
                ),
          ),
        ),
      ],
    );
  }
}
