import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/utils/cancel_token.dart';

void main() {
  test('a job is aborted once every waiter has cancelled', () async {
    final jobs = SharedJobs<String>();
    final done = Completer<String>();
    CancelToken? abort;
    Future<String> start(CancelToken a) {
      abort = a;
      a.onCancel(() => done.complete('aborted'));

      return done.future;
    }

    final first = CancelToken();
    final second = CancelToken();
    final a = jobs.run('k', first, start);
    final b = jobs.run('k', second, start);

    first.cancel();
    expect(abort!.isCancelled, isFalse);
    second.cancel();
    expect(abort!.isCancelled, isTrue);
    expect(await a, 'aborted');
    expect(await b, 'aborted');
  });

  test('a waiter without a token keeps the job alive', () async {
    final jobs = SharedJobs<String>();
    final done = Completer<String>();
    CancelToken? abort;
    Future<String> start(CancelToken a) {
      abort = a;

      return done.future;
    }

    final token = CancelToken();
    final a = jobs.run('k', token, start);
    final b = jobs.run('k', null, start);
    token.cancel();
    expect(abort!.isCancelled, isFalse);
    done.complete('ok');
    expect(await a, 'ok');
    expect(await b, 'ok');
  });

  test('a request joining an aborted job gets a fresh run', () async {
    final jobs = SharedJobs<int>();
    var runs = 0;
    final gates = <Completer<void>>[];
    Future<int> start(CancelToken a) async {
      final run = ++runs;
      final gate = Completer<void>();
      gates.add(gate);
      a.onCancel(gate.complete);
      await gate.future;

      return a.isCancelled ? -1 : run;
    }

    final token = CancelToken();
    final first = jobs.run('k', token, start);
    token.cancel();
    final second = jobs.run('k', CancelToken(), start);

    expect(await first, -1);
    await pumpEventQueue();
    gates.last.complete();
    expect(await second, 2);
  });
}
