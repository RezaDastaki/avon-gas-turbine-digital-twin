function sev_combos = GetSeverityCombinations(fault_type)
% GetSeverityCombinations - Returns severity combination definitions
%
% Inputs:
%   fault_type - 'dual', 'triple', or 'quad'
%
% Returns:
%   sev_combos - Struct with fields D1-D4, T1-T8, or Q1-Q12
%       Each field contains:
%           .severities - Array of severity levels
%           .severity_percents - Array of percentages
%           .description - Text description
%
% Date: 2025-12-29

switch lower(fault_type)
    case 'dual'
        %% Dual-Fault Severity Combinations (4)

        sev_combos.D1.severities = [1, 1];
        sev_combos.D1.severity_percents = [20, 20];
        sev_combos.D1.description = 'Both incipient (SEV1: 20%+20%)';

        sev_combos.D2.severities = [2, 2];
        sev_combos.D2.severity_percents = [40, 40];
        sev_combos.D2.description = 'Both moderate (SEV2: 40%+40%)';

        sev_combos.D3.severities = [3, 3];
        sev_combos.D3.severity_percents = [60, 60];
        sev_combos.D3.description = 'Both severe (SEV3: 60%+60%)';

        sev_combos.D4.severities = [1, 4];
        sev_combos.D4.severity_percents = [20, 80];
        sev_combos.D4.description = 'Asymmetric (SEV1+SEV4: 20%+80%)';

    case 'triple'
        %% Triple-Fault Severity Combinations (8)

        sev_combos.T1.severities = [1, 1, 1];
        sev_combos.T1.severity_percents = [20, 20, 20];
        sev_combos.T1.description = 'All incipient (SEV1: 20%+20%+20%)';

        sev_combos.T2.severities = [2, 2, 2];
        sev_combos.T2.severity_percents = [40, 40, 40];
        sev_combos.T2.description = 'All moderate (SEV2: 40%+40%+40%)';

        sev_combos.T3.severities = [3, 3, 3];
        sev_combos.T3.severity_percents = [60, 60, 60];
        sev_combos.T3.description = 'All severe (SEV3: 60%+60%+60%)';

        sev_combos.T4.severities = [4, 4, 4];
        sev_combos.T4.severity_percents = [80, 80, 80];
        sev_combos.T4.description = 'All critical (SEV4: 80%+80%+80%)';

        sev_combos.T5.severities = [1, 2, 3];
        sev_combos.T5.severity_percents = [20, 40, 60];
        sev_combos.T5.description = 'Linear progression (SEV1+2+3: 20%+40%+60%)';

        sev_combos.T6.severities = [1, 3, 4];
        sev_combos.T6.severity_percents = [20, 60, 80];
        sev_combos.T6.description = 'Accelerating (SEV1+3+4: 20%+60%+80%)';

        sev_combos.T7.severities = [2, 3, 4];
        sev_combos.T7.severity_percents = [40, 60, 80];
        sev_combos.T7.description = 'Late stage (SEV2+3+4: 40%+60%+80%)';

        sev_combos.T8.severities = [1, 1, 4];
        sev_combos.T8.severity_percents = [20, 20, 80];
        sev_combos.T8.description = 'One critical (SEV1+1+4: 20%+20%+80%)';

    case 'quad'
        %% Quad-Fault Severity Combinations (12)

        sev_combos.Q1.severities = [1, 1, 1, 1];
        sev_combos.Q1.severity_percents = [20, 20, 20, 20];
        sev_combos.Q1.description = 'All incipient (SEV1: 20%+20%+20%+20%)';

        sev_combos.Q2.severities = [2, 2, 2, 2];
        sev_combos.Q2.severity_percents = [40, 40, 40, 40];
        sev_combos.Q2.description = 'All moderate (SEV2: 40%+40%+40%+40%)';

        sev_combos.Q3.severities = [3, 3, 3, 3];
        sev_combos.Q3.severity_percents = [60, 60, 60, 60];
        sev_combos.Q3.description = 'All severe (SEV3: 60%+60%+60%+60%)';

        sev_combos.Q4.severities = [4, 4, 4, 4];
        sev_combos.Q4.severity_percents = [80, 80, 80, 80];
        sev_combos.Q4.description = 'All critical (SEV4: 80%+80%+80%+80%)';

        sev_combos.Q5.severities = [1, 1, 2, 2];
        sev_combos.Q5.severity_percents = [20, 20, 40, 40];
        sev_combos.Q5.description = 'Two-tier low-mid (SEV1+2: 20%+20%+40%+40%)';

        sev_combos.Q6.severities = [2, 2, 3, 3];
        sev_combos.Q6.severity_percents = [40, 40, 60, 60];
        sev_combos.Q6.description = 'Two-tier mid-high (SEV2+3: 40%+40%+60%+60%)';

        sev_combos.Q7.severities = [3, 3, 4, 4];
        sev_combos.Q7.severity_percents = [60, 60, 80, 80];
        sev_combos.Q7.description = 'Two-tier high-critical (SEV3+4: 60%+60%+80%+80%)';

        sev_combos.Q8.severities = [1, 2, 3, 4];
        sev_combos.Q8.severity_percents = [20, 40, 60, 80];
        sev_combos.Q8.description = 'Linear progression (SEV1+2+3+4: 20%+40%+60%+80%)';

        sev_combos.Q9.severities = [1, 1, 1, 4];
        sev_combos.Q9.severity_percents = [20, 20, 20, 80];
        sev_combos.Q9.description = 'One critical dominant (SEV1+1+1+4: 20%+20%+20%+80%)';

        sev_combos.Q10.severities = [1, 2, 2, 4];
        sev_combos.Q10.severity_percents = [20, 40, 40, 80];
        sev_combos.Q10.description = 'Mixed with critical (SEV1+2+2+4: 20%+40%+40%+80%)';

        sev_combos.Q11.severities = [2, 3, 3, 4];
        sev_combos.Q11.severity_percents = [40, 60, 60, 80];
        sev_combos.Q11.description = 'Escalating to failure (SEV2+3+3+4: 40%+60%+60%+80%)';

        sev_combos.Q12.severities = [1, 3, 3, 4];
        sev_combos.Q12.severity_percents = [20, 60, 60, 80];
        sev_combos.Q12.description = 'Jump pattern (SEV1+3+3+4: 20%+60%+60%+80%)';

    otherwise
        error('fault_type must be: dual, triple, or quad');
end

end
