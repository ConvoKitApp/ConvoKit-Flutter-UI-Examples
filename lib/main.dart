import 'package:flutter/material.dart';

import 'showcase/component_showcase_app.dart';

void main() {
  runApp(
    ComponentShowcaseApp(
      initialVariant: ShowcaseVariant.fromName(
        Uri.base.queryParameters['variant'],
      ),
    ),
  );
}
