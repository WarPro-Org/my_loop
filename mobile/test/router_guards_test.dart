import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/app/router_guards.dart';

/// Router guards for #130 (ML-ERR-033): authRedirect fail-closes unauthenticated deep-links
/// into protected routes.
void main() {
  group('authRedirect', () {
    test('unauthenticated on a protected route is bounced to /login', () {
      expect(authRedirect(isAuthenticated: false, location: '/home'), '/login');
      expect(authRedirect(isAuthenticated: false, location: '/journey'), '/login');
      expect(authRedirect(isAuthenticated: false, location: '/achievements'), '/login');
      // Onboarding routes require a session, so an unauth caller is bounced too.
      expect(authRedirect(isAuthenticated: false, location: '/avatar'), '/login');
      expect(authRedirect(isAuthenticated: false, location: '/set-home'), '/login');
    });

    test('unauthenticated on an auth route is allowed (no login bounce loop)', () {
      expect(authRedirect(isAuthenticated: false, location: '/login'), isNull);
      expect(authRedirect(isAuthenticated: false, location: '/local-signup'), isNull);
    });

    test('authenticated is never redirected away — /login stays the bootstrap screen', () {
      // Crucially NOT forced to /home: the login screen runs session bootstrap first.
      expect(authRedirect(isAuthenticated: true, location: '/login'), isNull);
      expect(authRedirect(isAuthenticated: true, location: '/home'), isNull);
      expect(authRedirect(isAuthenticated: true, location: '/avatar'), isNull);
    });
  });
}
