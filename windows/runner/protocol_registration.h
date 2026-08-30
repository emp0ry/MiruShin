#ifndef RUNNER_PROTOCOL_REGISTRATION_H_
#define RUNNER_PROTOCOL_REGISTRATION_H_

// Repairs the per-user mirushin:// registration for the currently running
// executable. Failures are non-fatal so a locked-down machine can still start.
void RepairMiruShinProtocolRegistration();

// Deletes the protocol key only if its command still targets this executable.
void RemoveMiruShinProtocolRegistrationIfOwned();

#endif  // RUNNER_PROTOCOL_REGISTRATION_H_
