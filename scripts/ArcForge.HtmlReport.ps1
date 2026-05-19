# ArcForge First Response - HTML Report Helpers
#
# This module supports ArcForge's static HTML report.
#
# Important boundaries:
# - Keep the HTML report local, self-contained, auditable, and dependency-free.
# - Do not collect endpoint evidence in this module.
# - Do not run health checks in this module.
# - Do not change readiness scoring in this module.
# - Do not write console or TXT report output in this module.
# - Do not add JavaScript, CDN assets, remote fonts, remote icons, remote images,
#   or external dependencies in this module.
#
# v0.41 extraction scope:
# - ConvertTo-HtmlSafeText remains the shared HTML encoding helper.
# - New-StatusClass owns small status-to-CSS-class lookups used by the HTML
#   report.
# - New-StatusBadgeHtml owns simple status badge markup used by the HTML report.
# - ConvertTo-ArcForgeHtmlFindingList owns generic finding-line list markup used
#   by the HTML report.
# - Get-ArcForgeFlattenedLines owns generic line flattening used by the HTML
#   report.
# - Get-ArcForgeSectionReadiness owns Readiness Overview card data prepared
#   from already-captured report section lines.
# - New-ArcForgeReadinessOverviewHtml owns the static Readiness Overview card
#   markup used by the HTML report.
# - New-ArcForgeHtmlReport remains in Invoke-ArcForgeFirstResponse.ps1 for now.
# - Future releases can move additional HTML helpers in small, tested slices.

function ConvertTo-HtmlSafeText {
    param (
        [string]$Text
    )

    # Encode text before placing it into HTML.
    #
    # This prevents report values containing characters like <, >, or & from
    # breaking the HTML structure or being interpreted as markup.
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-StatusClass {
    param (
        [string]$Status,
        [string]$ClassPrefix = "status"
    )

    # Map an existing ArcForge status label to the matching static HTML CSS
    # class. This is presentation-only; it does not change findings, scoring, or
    # console/TXT report output.
    switch ($Status) {
        "OK"                    { return "$ClassPrefix-ok" }
        "WARN"                  { return "$ClassPrefix-warn" }
        "FAIL"                  { return "$ClassPrefix-fail" }
        "Healthy"               { return "$ClassPrefix-ok" }
        "Attention Recommended" { return "$ClassPrefix-warn" }
        "Action Required"       { return "$ClassPrefix-fail" }
        default                 { return "$ClassPrefix-unknown" }
    }
}

function New-StatusBadgeHtml {
    param (
        [string]$Status,
        [string]$StatusClass,
        [string]$BadgeClass = "status-badge"
    )

    # Build a small status badge for the static HTML report.
    #
    # The status text is encoded before it is inserted into markup. The CSS class
    # values are controlled by ArcForge helper logic, not endpoint input.
    $SafeStatus = ConvertTo-HtmlSafeText $Status

    return "<span class=`"$BadgeClass $StatusClass`">$SafeStatus</span>"
}

function ConvertTo-ArcForgeHtmlFindingList {
    param (
        [object[]]$Lines,
        [string]$EmptyMessage = "No findings captured for this section. See Raw Findings for the complete report output."
    )

    # Convert raw finding lines into an HTML <li> list.
    #
    # Some section line collections can be nested arrays, especially when multiple
    # report sections are combined into one HTML card. This helper flattens them,
    # removes blanks, HTML-encodes every line, and wraps each finding in <code>.
    #
    # Output:
    # - A string containing one or more <li> elements.
    # - A muted placeholder <li> when the section has no findings.
    $FlattenedLines = @(
        foreach ($Line in $Lines) {
            if ($null -eq $Line) {
                continue
            }

            if ($Line -is [System.Collections.IEnumerable] -and $Line -isnot [string]) {
                foreach ($Item in $Line) {
                    if ($null -ne $Item) {
                        [string]$Item
                    }
                }
            }
            else {
                [string]$Line
            }
        }
    )

    $CleanLines = @(
        $FlattenedLines |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ConvertTo-HtmlSafeText $_ }
    )

    if (-not $CleanLines -or $CleanLines.Count -eq 0) {
        return "<li class=`"muted`">$(ConvertTo-HtmlSafeText $EmptyMessage)</li>"
    }

    return ($CleanLines | ForEach-Object {
        "<li><code>$_</code></li>"
    }) -join "`n"
}

# Flattens nested line arrays into a simple string array.
#
# Used by readiness scoring so combined sections like System can be counted
# the same way as single sections like Network or Security.
function Get-ArcForgeFlattenedLines {
    param (
        [object[]]$Lines
    )

    return @(
        foreach ($Line in $Lines) {
            if ($null -eq $Line) {
                continue
            }

            if ($Line -is [System.Collections.IEnumerable] -and $Line -isnot [string]) {
                foreach ($Item in $Line) {
                    if ($null -ne $Item) {
                        [string]$Item
                    }
                }
            }
            else {
                [string]$Line
            }
        }
    )
}

# Scores one report area for the Readiness Overview cards.
#
# This helper prepares card data from already-captured report section lines. It
# does not run checks, write output, change scoring, or assemble the final HTML
# document.
#
# Output:
# - PSCustomObject containing name, status label, CSS class, counts, and summary.
function Get-ArcForgeSectionReadiness {
    param (
        [string]$Name,
        [object[]]$Lines
    )

    $FlattenedLines = Get-ArcForgeFlattenedLines -Lines $Lines

    $OkCount = @($FlattenedLines | Where-Object { $_ -match '^\[OK\]' }).Count
    $WarnCount = @($FlattenedLines | Where-Object { $_ -match '^\[WARN\]' }).Count
    $FailCount = @($FlattenedLines | Where-Object { $_ -match '^\[FAIL\]' }).Count

    if ($FailCount -gt 0) {
        $Status = "Critical"
        $StatusClass = "readiness-critical"
        $Summary = "Critical findings require attention."
    }
    elseif ($WarnCount -gt 0) {
        $Status = "Attention"
        $StatusClass = "readiness-attention"
        $Summary = "Warnings found. Review recommended actions."
    }
    elseif ($OkCount -gt 0) {
        $Status = "OK"
        $StatusClass = "readiness-ok"
        $Summary = "All checks passed."
    }
    else {
        $Status = "No Data"
        $StatusClass = "readiness-neutral"
        $Summary = "No findings detected in this section."
    }

    [pscustomobject]@{
        Name        = $Name
        Status      = $Status
        StatusClass = $StatusClass
        OkCount     = $OkCount
        WarnCount   = $WarnCount
        FailCount   = $FailCount
        Summary     = $Summary
    }
}

    # Builds the HTML block for the Readiness Overview dashboard cards.
    #
    # The card data is prepared by Get-ArcForgeSectionReadiness. This helper only
    # converts those objects into HTML markup for the final report.
    # Future module owner: scripts/ArcForge.Html.Navigation.ps1
    function New-ArcForgeReadinessOverviewHtml {
        param (
            [object[]]$ReadinessCards
        )

        $CardBlocks = @()

        foreach ($Card in $ReadinessCards) {
            $SafeName = ConvertTo-HtmlSafeText $Card.Name
            $SafeStatus = ConvertTo-HtmlSafeText $Card.Status
            $SafeSummary = ConvertTo-HtmlSafeText $Card.Summary

            # v0.22 presentation-only status classes.
            # These classes control the left-border accent for the Readiness
            # Overview cards. They do not change the underlying status values
            # or the shared StatusClass property used elsewhere in the HTML.
            $CardVisualClass = switch ($Card.Status) {
                "OK"        { "readiness-card-ok" }
                "Attention" { "readiness-card-warn" }
                "Critical"  { "readiness-card-fail" }
                default     { "readiness-card-unknown" }
            }

            # v0.22 presentation-only navigation target.
            # The Readiness Overview cards now behave like dashboard shortcuts.
            # Each card jumps to the matching detailed report section by using
            # the same static anchor IDs already used by the sidebar navigation.
            #
            # Important:
            # - This is only an HTML link target.
            # - No JavaScript is used.
            # - This does not change check logic, console output, or TXT output.
            # - If a card does not jump correctly, compare these anchor values
            #   with the matching id="section-name" values in the HTML sections.
            $CardAnchor = switch ($Card.Name) {
                "System"             { "system" }
                "Network"            { "network" }
                "Software Readiness" { "software-readiness" }
                "Security"           { "security" }
                "Updates"            { "updates" }
                default              { "readiness-overview" }
            }

            $SafeCardAnchor = ConvertTo-HtmlSafeText $CardAnchor

            $CardBlocks += @"
            <a class="readiness-card-link" href="#$SafeCardAnchor" title="Jump to $SafeName details" aria-label="Jump to $SafeName details">
                <article class="readiness-card $($Card.StatusClass) $CardVisualClass">
                    <div class="readiness-card-header">
                        <h3>$SafeName</h3>
                        <span class="readiness-status">$SafeStatus</span>
                    </div>
                    <div class="readiness-counts" aria-label="$SafeName readiness counts">
                        <span class="readiness-count-item readiness-count-ok"><strong>$($Card.OkCount)</strong><span>OK</span></span>
                        <span class="readiness-count-item readiness-count-warn"><strong>$($Card.WarnCount)</strong><span>WARN</span></span>
                        <span class="readiness-count-item readiness-count-fail"><strong>$($Card.FailCount)</strong><span>FAIL</span></span>
                    </div>
                    <p class="readiness-card-summary">$SafeSummary</p>
                </article>
            </a>
"@
        }

        $CardsHtml = $CardBlocks -join "`n"

        return @"
        <section id="readiness-overview" class="card section">
            <div class="section-title">
                <h2>Readiness Overview</h2>
                <p>Dashboard-style summary of major battlestation readiness areas.</p>
            </div>
            <div class="readiness-grid">
$CardsHtml
            </div>
        </section>
"@
    }
