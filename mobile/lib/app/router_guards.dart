/// Route-guard logic for the app router, kept in its own file so tests can exercise it
/// WITHOUT importing `router.dart` — which pulls in every screen (home_tab, journey, …)
/// and would drag thousands of uncovered UI lines into the coverage denominator (#130).
library;

/// Where a signed-out user lands.
const loginRoute = '/login';

/// Routes reachable without a signed-in session. Everything else is protected.
///
/// Onboarding routes (`/avatar`, `/set-home`) are intentionally NOT here: they are
/// only reached once Firebase already has a session, so an *unauthenticated* caller
/// deep-linking to them should still be bounced to `/login`.
const authRoutes = {loginRoute, '/local-signup'};

/// Pure route guard (see the router's `redirect`). Returns the path to redirect to,
/// or `null` to allow the navigation.
///
/// Fail-closed: an unauthenticated caller may only sit on an auth route; any other
/// target sends them to `/login`. Authenticated callers are never redirected away
/// from `/login` here — the login screen performs the session bootstrap (profile
/// load, slice hydration, SignalR connect, push init) and then navigates onward
/// itself, so short-circuiting it would launch the app with unhydrated state.
///
/// Offline is handled implicitly: Firebase restores the session from disk with no
/// network, so [isAuthenticated] is true offline and a cached user is not bounced.
String? authRedirect({required bool isAuthenticated, required String location}) {
  if (!isAuthenticated && !authRoutes.contains(location)) return loginRoute;
  return null;
}
