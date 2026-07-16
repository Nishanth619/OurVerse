
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    var search = await yt.search.search('baby');
    var list = search.toList();
    print('Found: ' + list.length.toString() + ' results');
  } catch(e, st) {
    print('Error: ' + e.toString());
  }
  yt.close();
}
