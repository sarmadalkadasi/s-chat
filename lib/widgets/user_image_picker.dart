import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class UserImagePicker extends StatefulWidget {
  const UserImagePicker({super.key, required this.onSelectImage});

  final void Function(File image) onSelectImage;

  @override
  State<UserImagePicker> createState() => _UserImagePickerState();
}

class _UserImagePickerState extends State<UserImagePicker> {
  File? _pickedImage;

  void _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 65,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (image == null) {
      return;
    }
    setState(() {
      _pickedImage = File(image.path);
    });
    widget.onSelectImage(_pickedImage!);
  }

  void _selectImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 65,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (image == null) {
      return;
    }
    setState(() {
      _pickedImage = File(image.path);
    });
    widget.onSelectImage(_pickedImage!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            children: [CircleAvatar(
              radius: 52,
              backgroundColor: Theme.of(context).colorScheme.secondary.withAlpha(100),
              foregroundImage: _pickedImage != null
                  ? FileImage(_pickedImage!)
                  : null,
              child: const Icon(Icons.camera_alt),
            ),
            if(_pickedImage != null)
            Positioned(
              bottom: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withGreen(220),
                    borderRadius: BorderRadius.circular(200)
                  ),
                  child: Icon(Icons.edit,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,),
                )
            )
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _selectImage,
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
