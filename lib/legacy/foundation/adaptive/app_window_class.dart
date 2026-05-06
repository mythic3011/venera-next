enum AppWindowClass {
  compact,
  medium,
  wide,
}

AppWindowClass classifyAppWidth(double width) {
  if (width < 600) return AppWindowClass.compact;
  if (width < 840) return AppWindowClass.medium;
  return AppWindowClass.wide;
}
