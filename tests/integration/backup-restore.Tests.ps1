# Pester v5 review draft. Requires separately approved isolated lab execution.
Describe 'Phase 2 integration contract' {
    It 'never targets original recovery volume' {
        $compose = Get-Content "$PSScriptRoot/../../infrastructure/docker/compose.phase2.yaml" -Raw
        $compose | Should -Not -Match '\brecovery_data\b'
        $compose | Should -Match 'phase2_restore_data'
    }
    It 'uses a separate Compose project' {
        $compose = Get-Content "$PSScriptRoot/../../infrastructure/docker/compose.phase2.yaml" -Raw
        $compose | Should -Match 'name:\s*cloud-dr-phase2-validation'
    }
}
