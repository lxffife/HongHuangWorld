BEGIN;
CREATE TABLE parties (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
 world_instance_id UUID NOT NULL REFERENCES world_instances(id),
 leader_account_id UUID NOT NULL REFERENCES accounts(id),
 status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK(status IN ('active','disbanded')),
 max_members SMALLINT NOT NULL DEFAULT 5 CHECK(max_members BETWEEN 2 AND 8),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_parties_instance_status ON parties(world_instance_id,status);
CREATE TABLE party_members (
 party_id UUID NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
 account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
 role VARCHAR(12) NOT NULL DEFAULT 'member' CHECK(role IN ('leader','member')),
 joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(party_id,account_id),
 UNIQUE(account_id)
);
CREATE INDEX idx_party_members_character ON party_members(character_id);
CREATE TABLE party_invitations (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 party_id UUID NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
 inviter_account_id UUID NOT NULL REFERENCES accounts(id),
 invitee_account_id UUID NOT NULL REFERENCES accounts(id),
 status VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','declined','expired','revoked')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 expires_at TIMESTAMPTZ NOT NULL,
 responded_at TIMESTAMPTZ,
 CHECK(inviter_account_id <> invitee_account_id)
);
CREATE UNIQUE INDEX uq_party_pending_invitation ON party_invitations(party_id,invitee_account_id) WHERE status='pending';
CREATE INDEX idx_party_invitation_inbox ON party_invitations(invitee_account_id,status,expires_at);
COMMIT;
