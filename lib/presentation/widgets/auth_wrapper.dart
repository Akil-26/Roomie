import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:roomie/presentation/screens/auth/login_s.dart';
import 'package:roomie/presentation/screens/home/home_s.dart';
import 'package:roomie/presentation/screens/profile/user_details_s.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/firestore_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        // Show a loading indicator while waiting for the auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading Roomie...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // User is not logged in
        if (!snapshot.hasData || snapshot.data == null) {
          return const PhoneLoginScreen();
        }

        // User is logged in, check if profile is complete
        return FutureBuilder<Map<String, dynamic>?>(
          future: FirestoreService().getUserDetails(snapshot.data!.uid),
          builder: (context, userSnapshot) {
            // Show loading while checking user details
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Setting up your profile...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Check if user profile is complete
            final userDetails = userSnapshot.data;
            final bool profileIncomplete =
                userDetails == null ||
                userDetails['username'] == null ||
                userDetails['username'].toString().isEmpty;

            if (profileIncomplete) {
              // User needs to complete profile
              return const UserDetailsScreen(isFromPhoneSignup: true);
            } else {
              // User is fully set up, go to home
              // Use key with user ID to force widget recreation on account switch
              return HomeScreen(key: ValueKey(snapshot.data!.uid));
            }
          },
        );
      },
    );
  }
}
