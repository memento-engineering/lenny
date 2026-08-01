import 'package:leonard_devtools/src/thinking/append_only_text_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('append accumulates and notifies', () {
    final c = AppendOnlyTextController();
    int n = 0;
    c.addListener(() => n++);

    c.append('hello ');
    c.append('world');

    expect(c.text, 'hello world');
    expect(c.length, 'hello world'.length);
    expect(n, 2);
  });

  test('empty append is a no-op (no notification)', () {
    final c = AppendOnlyTextController();
    int n = 0;
    c.addListener(() => n++);

    c.append('');

    expect(c.text, isEmpty);
    expect(n, 0);
  });

  test('clear empties and notifies', () {
    final c = AppendOnlyTextController();
    c.append('x');
    int n = 0;
    c.addListener(() => n++);

    c.clear();

    expect(c.text, isEmpty);
    expect(n, 1);
  });

  test('clear on empty still notifies (turn boundary signal)', () {
    final c = AppendOnlyTextController();
    int n = 0;
    c.addListener(() => n++);

    c.clear();

    expect(n, 1);
  });
}
