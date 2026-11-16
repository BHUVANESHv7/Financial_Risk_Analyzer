import 'package:flutter_test/flutter_test.dart';
import 'package:loan_app/config.dart';

void main() {
  String api(String page, {bool same = false}) =>
      AppConfig.webApiUrl(Uri.parse(page), sameOrigin: same);

  test('deployed web app talks to its own origin', () {
    expect(api('https://loan-risk.onrender.com/#/home'), 'https://loan-risk.onrender.com');
    expect(api('https://bank.example.com:8443/'), 'https://bank.example.com:8443');
  });

  test('local Docker on :8000 uses the same origin', () {
    expect(api('http://localhost:8000/'), 'http://localhost:8000');
  });

  test('dev servers on other ports use the local API', () {
    expect(api('http://localhost:53122/'), 'http://127.0.0.1:8000');
    expect(api('http://127.0.0.1:5500/'), 'http://127.0.0.1:8000');
  });

  test('SAME_ORIGIN build forces the page origin', () {
    expect(api('http://localhost:8080/', same: true), 'http://localhost:8080');
  });
}
