// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * CareMitra Health Wallet (MVP)
 * ---------------------------------------------
 * What we store on-chain:
 *   • Hash (bytes32) of off-chain file (Supabase/IPFS) => proof of integrity
 *   • URI/pointer to off-chain file
 *   • Creator (doctor/hospital) + patient
 *   • Version tag + timestamp
 *   • Patient-controlled sharing (grant/revoke per-record and per-doctor)
 *
 * DO NOT put personal/medical plaintext on-chain. Keep PHI off-chain.
 */

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract HealthWallet is AccessControl, Pausable {
    // --- Roles ---
    bytes32 public constant ADMIN_ROLE    = keccak256("ADMIN_ROLE");
    bytes32 public constant HOSPITAL_ROLE = keccak256("HOSPITAL_ROLE");
    bytes32 public constant DOCTOR_ROLE   = keccak256("DOCTOR_ROLE");

// --- Record model ---
struct HealthRecord {
    uint256 id;
    address patient;              // EOA controlling access
    address creator;              // doctor/hospital address
    bytes32 contentHash;          // SHA-256/Keccak256 hash of the file
    string  uri;                  // off-chain pointer (IPFS, Supabase, HTTPS)
    string  version;              // "v1", "v2", etc.
    uint256 timestamp;            // block timestamp
}

// Auto-increment record id
uint256 private _nextRecordId = 1;

// Storage
mapping(uint256 => HealthRecord) private records; // recordId => HealthRecord
mapping(address => uint256[]) private recordsByPatient; // patient => recordIds

// Patient-wide approval: patient => doctor => approved?
mapping(address => mapping(address => bool)) public patientDoctorApproval;

// Record-specific access: recordId => doctor => approved?
mapping(uint256 => mapping(address => bool)) public recordAccess;

// --- Events ---
event HospitalAdded(address indexed hospital, address indexed by);
event HospitalRemoved(address indexed hospital, address indexed by);
event DoctorAdded(address indexed doctor, address indexed by);
event DoctorRemoved(address indexed doctor, address indexed by);
event RecordAdded(
    uint256 indexed recordId,
    address indexed patient,
    address indexed creator,
    bytes32 contentHash,
    string uri,
    string version,
    uint256 timestamp
);
event RecordShared(uint256 indexed recordId, address indexed patient, address indexed doctor);
event RecordAccessRevoked(uint256 indexed recordId, address indexed patient, address indexed doctor);
event DoctorApprovedForPatient(address indexed patient, address indexed doctor);
event DoctorRevokedForPatient(address indexed patient, address indexed doctor);
event AdminPaused(address indexed admin);
event AdminUnpaused(address indexed admin);


constructor(address admin) {
    // Grant deployer + provided admin the admin role
    _grantRole(ADMIN_ROLE, admin);
    _grantRole(ADMIN_ROLE, msg.sender);
    // Admins can grant/revoke all roles
    _setRoleAdmin(HOSPITAL_ROLE, ADMIN_ROLE);
    _setRoleAdmin(DOCTOR_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
}

// --- Admin: manage hospitals/doctors & emergency pause ---
function addHospital(address hospital) external onlyRole(ADMIN_ROLE) {
    _grantRole(HOSPITAL_ROLE, hospital);
    emit HospitalAdded(hospital, msg.sender);
}

function removeHospital(address hospital) external onlyRole(ADMIN_ROLE) {
    _revokeRole(HOSPITAL_ROLE, hospital);
    emit HospitalRemoved(hospital, msg.sender);
}

function addDoctor(address doctor) external onlyRole(ADMIN_ROLE) {
    _grantRole(DOCTOR_ROLE, doctor);
    emit DoctorAdded(doctor, msg.sender);
}

function removeDoctor(address doctor) external onlyRole(ADMIN_ROLE) {
    _revokeRole(DOCTOR_ROLE, doctor);
    emit DoctorRemoved(doctor, msg.sender);
}

function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
    emit Paused(msg.sender);
}

function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
    emit Unpaused(msg.sender);
}

// --- Patient consent (broad) ---
function approveDoctorForAllMyRecords(address doctor) external whenNotPaused {
    patientDoctorApproval[msg.sender][doctor] = true;
    emit DoctorApprovedForPatient(msg.sender, doctor);
}

function revokeDoctorForAllMyRecords(address doctor) external whenNotPaused {
    patientDoctorApproval[msg.sender][doctor] = false;
    emit DoctorRevokedForPatient(msg.sender, doctor);
}

// --- Create records (doctors or hospitals only) ---
/**
 * Add a new health record for a patient.
 * Requires either:
 *  - Patient has granted patient-wide approval to msg.sender; OR
 *  - The patient has explicitly shared this recordId later (recordAccess)
 *
 * Best practice: get patient Doctor-wide approval first.
 */
function addHealthRecord(
    address patient,
    bytes32 contentHash,
    string calldata uri,
    string calldata version
) external whenNotPaused onlyRole(DOCTOR_ROLE) {
    require(patient != address(0), "Invalid patient");
    require(contentHash != bytes32(0), "Invalid hash");
    require(bytes(uri).length > 0, "URI required");
    // either broad approval (recommended) or patient will share later per-record
    require(
        patientDoctorApproval[patient][msg.sender],
        "No patient-wide approval for this doctor"
    );

    uint256 id = _nextRecordId++;
    records[id] = HealthRecord({
        id: id,
        patient: patient,
        creator: msg.sender,
        contentHash: contentHash,
        uri: uri,
        version: version,
        timestamp: block.timestamp
    });
    recordsByPatient[patient].push(id);

    // since doctor is trusted for this patient, grant record-scoped access too
    recordAccess[id][msg.sender] = true;

    emit RecordAdded(id, patient, msg.sender, contentHash, uri, version, block.timestamp);
}

// --- Sharing (granular) ---
// Patient can share a specific record with a doctor
function shareRecord(uint256 recordId, address doctor) external whenNotPaused {
    HealthRecord memory r = records[recordId];
    require(r.id != 0, "Record not found");
    require(r.patient == msg.sender, "Only patient can share");
    require(hasRole(DOCTOR_ROLE, doctor), "Target is not a doctor");

    recordAccess[recordId][doctor] = true;
    emit RecordShared(recordId, msg.sender, doctor);
}

// Patient can revoke a doctor from a specific record
function revokeAccess(uint256 recordId, address doctor) external whenNotPaused {
    HealthRecord memory r = records[recordId];
    require(r.id != 0, "Record not found");
    require(r.patient == msg.sender, "Only patient can revoke");
    recordAccess[recordId][doctor] = false;
    emit RecordAccessRevoked(recordId, msg.sender, doctor);
}

// --- Read functions (no gas if called off-chain) ---
function getRecord(uint256 recordId)
    external
    view
    returns (HealthRecord memory)
{
    return records[recordId];
}

function getPatientRecordIds(address patient) external view returns (uint256[] memory) {
    return recordsByPatient[patient];
}

// Doctor can fetch a record only if they have access (patient-wide or record-specific)
function doctorCanViewRecord(uint256 recordId, address doctor) public view returns (bool) {
    HealthRecord memory r = records[recordId];
    if (r.id == 0) return false;
    if (!hasRole(DOCTOR_ROLE, doctor)) return false;

    // broad approval OR record-specific share
    return patientDoctorApproval[r.patient][doctor] || recordAccess[recordId][doctor];
}

// Verify a record by its hash
function verifyRecordHash(bytes32 contentHash)
    external
    view
    returns (bool exists, uint256 recordId, address patient, string memory version)
{
    // naive scan; for production, index hash => recordId mapping
    // Keep it simple for MVP.
    // NOTE: Off-chain index via events is recommended for scalability.
    for (uint256 i = 1; i < _nextRecordId; i++) {
        if (records[i].contentHash == contentHash) {
            HealthRecord memory r = records[i];
            return (true, r.id, r.patient, r.version);
        }
    }
    return (false, 0, address(0), "");
}
}