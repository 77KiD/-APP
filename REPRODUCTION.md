# Bug Reproduction: Invite Code Write Failure

## Issue Summary
User A generated invite code 7C43CBKF, but the code never reached Firestore. User B received "找不到這個邀請碼". Console confirmed no `invites` collection exists.

## Root Cause
**Clock skew issue**: When phone clock is slightly fast, `_inviteExpiresAt()` calculates `expiresAt > request.time + 1h`, violating rules constraint. Write is denied with `permission-denied`, but app swallows error and displays code as valid.

## Reproduction Steps with Emulator

### Prerequisites
```bash
npm install -g firebase-tools
cd /workspace
npm --prefix rules-tests install
```

### Step 1: Start Firestore Emulator
```bash
npx firebase emulators:start --only firestore --project demo-app
```

### Step 2: Run Rules Tests (in another terminal)
```bash
cd /workspace
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
npm --prefix rules-tests test
```

### Step 3: Verify the Clock Skew Test
Look for the test output:
```
✓ tolerates clock skew up to ±5min when creating invites
```

This test verifies:
- `expiresAt = request.time + 1h + 5min` ✅ accepted (upper tolerance)
- `expiresAt = request.time + 1h - 5min` ✅ accepted (lower tolerance)
- `expiresAt = request.time + 1h + 5min + 1sec` ❌ rejected (too high)
- `expiresAt = request.time + 1h - 5min - 1sec` ❌ rejected (too low)

## Manual Reproduction (Before Fix)

### Simulate Fast Phone Clock
1. **Setup**: User doc exists, trip creation succeeds
2. **Trigger**: Create invite with `expiresAt = server time + 1h + 6min` (simulating phone clock +6min fast)
3. **Old Rules (ea87aef)**: Write denied with `permission-denied`
4. **Old App Behavior**: 
   - `_trySync()` catches exception silently
   - Code saved locally and displayed to user
   - Console shows no `invites` collection
5. **User B tries to join**: Gets "找不到這個邀請碼"

### After Fix
1. **New Rules**: ±5min tolerance accepts the write
2. **New App**: If write still fails, throws error instead of displaying code
3. **Logging**: Raw FirebaseException printed to console

## Verification Checklist

- [ ] Rules tests pass with emulator
- [ ] App tests pass (offline_trip_repository_test.dart)
- [ ] CI passes
- [ ] Rules deployed to peers-bea4b
- [ ] Manual test: Create trip with APK on real device, verify invite code works
- [ ] Manual test: Verify join flow shows distinct errors for not-found/expired/permission-denied

## Files Changed
- `firestore.rules` - Added ±5min tolerance to `expiresOneServerHourFromNow()`
- `rules-tests/tests/firestore.rules.test.ts` - Added clock skew test
- `app/lib/features/trip/data/offline_trip_repository.dart` - Changed to throw errors instead of swallowing
- `app/lib/features/trip/data/firestore_trip_remote.dart` - Added logging and distinct error handling
- `app/lib/features/trip/domain/trip_models.dart` - Added JoinPermissionDeniedException and JoinNetworkException
- `app/lib/l10n/app_strings.dart` - Added distinct join error messages
