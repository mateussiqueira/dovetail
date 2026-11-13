import 'dart:convert';

List<String> ownUnformattedPaths(String output) => const LineSplitter()
    .convert(output)
    .where((String line) => line.startsWith('Changed '))
    .map((String line) => line.substring(8).replaceAll(r'\', '/'))
    .where(
      (String path) =>
          !path.contains('/cargokit/') && !path.contains('/build/'),
    )
    .toList();
