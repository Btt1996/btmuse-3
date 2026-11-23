import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Batch 2 follow-up: the MiniPlayer lives in AppShell AND as the
/// `bottomNavigationBar` of pushed import routes, each rendering
/// `Hero(tag: 'artwork-<trackId>')`. Flutter only errors when ONE route's
/// subtree holds two heroes with the same tag, so this topology — one
/// hero per route — must push, pop, and open the fullscreen sheet
/// without a duplicate-hero error. The test mirrors that topology with
/// plain Heroes carrying the same tag MiniPlayer uses.
///
/// It verifies the framework behavior for our exact tag layout, not the
/// pixel-level artwork hop: the hop (mini → pushed-route mini on pop)
/// is a small vertical flight between two bottom-anchored players.
void main() {
  const tag = 'artwork-track-1';

  Widget heroBox(Color color) {
    return Hero(
      tag: tag,
      child: Container(width: 44, height: 44, color: color),
    );
  }

  testWidgets('same Hero tag on home + pushed route: push/pop is clean',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    heroBox(Colors.pink),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              body: Center(child: heroBox(Colors.purple)),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open import route'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open import route'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Pop back: the artwork flies from the pushed route's mini player
    // to the home mini player. Still no duplicate-hero error.
    // (pageBack() needs a back button; this route has none, so pop the
    // Navigator directly.)
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('same Hero tag in a modal sheet: open/close is clean',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    heroBox(Colors.pink),
                    ElevatedButton(
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => Center(child: heroBox(Colors.blue)),
                        );
                      },
                      child: const Text('Open player sheet'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open player sheet'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
