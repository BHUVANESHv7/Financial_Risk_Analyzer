import 'package:flutter_test/flutter_test.dart';
import 'package:loan_app/controllers/applications_controller.dart';
import 'package:loan_app/services/realtime_service.dart';

Map<String, dynamic> app(int id, String status, {String risk = 'MEDIUM', String name = 'A'}) => {
      'id': id,
      'applicant_name': name,
      'status': status,
      'risk_level': risk,
      'decision': 'MANUAL REVIEW',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  late RealtimeService rt;
  late ApplicationsController c;

  setUp(() {
    rt = RealtimeService();
    c = ApplicationsController(rt)..status = 'PENDING'; // officer review queue
  });

  tearDown(() {
    c.dispose();
    rt.dispose();
  });

  Future<void> emit(String type, Map<String, dynamic> data) async {
    rt.debugEmit(LiveEvent(type, data));
    await Future<void>.delayed(Duration.zero); // let the stream deliver
  }

  test('new matching application is inserted at the top and highlighted', () async {
    await emit('application.created', app(1, 'PENDING'));
    await emit('application.created', app(2, 'PENDING'));
    expect(c.items.map((a) => a.id), [2, 1]);
    expect(c.total, 2);
    expect(c.highlighted, containsAll([1, 2]));
  });

  test('applications outside the current filter are ignored', () async {
    await emit('application.created', app(3, 'APPROVED'));
    expect(c.items, isEmpty);
  });

  test('a review that moves an item out of the filter removes it', () async {
    await emit('application.created', app(4, 'PENDING'));
    await emit('application.updated', app(4, 'APPROVED'));
    expect(c.items, isEmpty);
    expect(c.total, 0);
  });

  test('duplicate create events are not added twice', () async {
    await emit('application.created', app(5, 'PENDING'));
    await emit('application.created', app(5, 'PENDING'));
    expect(c.items.length, 1);
  });

  test('search filter applies to live events', () async {
    c.search = 'priya';
    await emit('application.created', app(6, 'PENDING', name: 'Ravi Kumar'));
    await emit('application.created', app(7, 'PENDING', name: 'Priya Sharma'));
    expect(c.items.map((a) => a.id), [7]);
  });
}
