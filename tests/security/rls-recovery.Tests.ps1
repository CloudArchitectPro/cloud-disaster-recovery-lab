# Pester v5 review draft: static policy-preservation assertions only.
Describe 'Phase 1 tenant policy preservation' {
    It 'retains three tenant SELECT policies' {
        $sql = Get-Content "$PSScriptRoot/../../sample-data/schema.sql" -Raw
        foreach ($policy in @('org_tenant_read','asset_tenant_read','event_tenant_read')) {
            $sql | Should -Match $policy
        }
    }
    It 'provisions no BYPASSRLS backup role' {
        $sql = Get-Content "$PSScriptRoot/../../scripts/sql/phase2-source-provision.sql" -Raw
        $sql | Should -Match 'NOBYPASSRLS'
        $sql | Should -Not -Match 'CREATE ROLE lab_backup[^;]*\sBYPASSRLS\s*;'
    }
}
