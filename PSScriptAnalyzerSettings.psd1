@{
    # High-signal rules we want to block on for shipped overlay/installer code
    IncludeRules = @(
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSReviewUnusedParameter',
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        PSAvoidUsingEmptyCatchBlock                 = @{ Severity = 'Error' }
        PSAvoidAssignmentToAutomaticVariable        = @{ Severity = 'Error' }
        PSReviewUnusedParameter                     = @{ Severity = 'Error' }
        PSUseShouldProcessForStateChangingFunctions = @{ Severity = 'Error' }
    }
}

