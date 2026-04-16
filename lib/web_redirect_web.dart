import 'dart:html' as html;

Future<bool> openInSameTab(String url) async {
  html.window.location.replace(url);
  return true;
}
