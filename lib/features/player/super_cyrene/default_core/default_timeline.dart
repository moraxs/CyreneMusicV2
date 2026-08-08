import 'default_types.dart';

/// Direct port of default-timeline.ts/findTimelineLine.
int findDefaultTimelineLine(List<DefaultLine> lines, double time) {
  var activeIndex = -1;
  for (var index = 0; index < lines.length; index++) {
    if (time < lines[index].startTime) break;
    activeIndex = index;
  }
  return activeIndex;
}
