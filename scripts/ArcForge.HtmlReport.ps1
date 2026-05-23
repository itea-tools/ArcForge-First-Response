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
# v0.52 extraction scope:
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
# - New-ArcForgeSidebarStatusSegmentsHtml owns the small static sidebar status
#   segment markup used by Report Navigation.
# - New-ArcForgeReportNavigationHtml owns the static Report Navigation/sidebar
#   markup used by the HTML report.
# - New-ArcForgeSystemCollapsibleCardHtml owns shared static <details> card
#   markup used by the System Overview and System detail sections.
# - New-ArcForgeSystemDetailSectionHtml owns static System detail section
#   markup built from explicit parameters and module-owned System helpers.
# - New-ArcForgeSystemOverviewHtml owns the static default-open System Overview
#   wrapper built from already-prepared System snapshot panel HTML.
# - New-ArcForgeSystemPanelHtml owns static System snapshot panel markup
#   built from already-prepared row HTML and explicit link parameters.
# - New-ArcForgeSystemPanelGroupHtml owns static System snapshot panel
#   group assembly from caller-prepared panel definitions.
# - New-ArcForgeSystemEvidenceRowHtml owns static System evidence row markup
#   built from an explicit record and optional display label.
# - New-ArcForgeSystemStatusLabelRowHtml owns static compact System
#   status/label row markup built from an explicit record and optional display
#   label.
# - ConvertTo-ArcForgeSystemEvidenceRecord owns static System report-line parsing
#   for existing OK/WARN/FAIL evidence rows.
# - New-ArcForgeSystemEvidenceOnlyRowHtml owns static System evidence-only row
#   markup built from an explicit record and optional display label.
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

# -----------------------------------------------------------------------------
# System Presentation Helpers
# -----------------------------------------------------------------------------
# These helpers do not collect evidence, change scoring, or alter console/TXT
# output. They only build static System HTML from prepared values.

# Converts one raw finding line like:
# [OK] OS Name: Microsoft Windows 10...
# into a small object the HTML renderer can place in a key/value row.
#
# v0.49: Moved from New-ArcForgeSystemEvidenceHtml after confirming it only
# depends on one explicit line, static report-line parsing rules, string
# trimming, and basic object creation.
# Module owner: scripts/ArcForge.HtmlReport.ps1
function ConvertTo-ArcForgeSystemEvidenceRecord {
    param (
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    $Pattern = '^\[(OK|WARN|FAIL)\]\s+(.+?:)\s*(.*)$'
    if ($Line -notmatch $Pattern) {
        return $null
    }

    return [pscustomobject]@{
        Status = $Matches[1]
        Label  = $Matches[2].Trim()
        Value  = $Matches[3].Trim()
    }
}

# Renders a single compact status-first key/value row.
# The status class only affects the HTML report and does not change
# readiness scoring or report data.
# v0.45: Moved from the main renderer after confirming it only depends on an
# explicit record, optional display label, New-StatusClass, and
# ConvertTo-HtmlSafeText.
# Module owner: scripts/ArcForge.HtmlReport.ps1
function New-ArcForgeSystemEvidenceRowHtml {
    param (
        [object]$Record,
        [string]$DisplayLabel
    )

    $Status = if ($Record.Status) { [string]$Record.Status } else { "UNKNOWN" }
    $StatusClass = New-StatusClass -Status $Status -ClassPrefix "system-status"

    $Label = if ([string]::IsNullOrWhiteSpace($DisplayLabel)) { $Record.Label } else { $DisplayLabel }
    $SafeStatus = ConvertTo-HtmlSafeText $Status
    $SafeLabel = ConvertTo-HtmlSafeText (($Label -replace ':$', '').Trim())
    $SafeValue = ConvertTo-HtmlSafeText $Record.Value

    return @"
            <div class="system-evidence-row">
                <span class="system-status-pill $StatusClass">$SafeStatus</span>
                <span class="system-evidence-label">$SafeLabel</span>
                <span class="system-evidence-value">$SafeValue</span>
            </div>
"@
}

# Renders a compact status + label row for System snapshot cards.
# Use this when the overview should communicate the signal without cramming long
# evidence values into a narrow responsive card. The full evidence value should
# remain available in the matching details section.
# v0.46: Moved from the main renderer after confirming it only depends on an
# explicit record, optional display label, New-StatusClass, and
# ConvertTo-HtmlSafeText.
# Module owner: scripts/ArcForge.HtmlReport.ps1
function New-ArcForgeSystemStatusLabelRowHtml {
    param (
        [object]$Record,
        [string]$DisplayLabel
    )

    $Status = if ($Record.Status) { [string]$Record.Status } else { "UNKNOWN" }
    $StatusClass = New-StatusClass -Status $Status -ClassPrefix "system-status"

    $Label = if ([string]::IsNullOrWhiteSpace($DisplayLabel)) { $Record.Label } else { $DisplayLabel }
    $SafeStatus = ConvertTo-HtmlSafeText $Status
    $SafeLabel = ConvertTo-HtmlSafeText (($Label -replace ':$', '').Trim())

    return @"
                    <div class="system-status-label-row">
                        <span class="system-status-pill $StatusClass">$SafeStatus</span>
                        <span class="system-evidence-label">$SafeLabel</span>
                    </div>
"@
}

function New-ArcForgeSystemEvidenceOnlyRowHtml {
    param (
        [object]$Record,
        [string]$DisplayLabel
    )

    # Render identity/platform evidence without a health-style OK/WARN/FAIL
    # pill. Endpoint identity fields are evidence capture values, not pass/fail
    # health checks, so this quieter row avoids implying a status verdict.
    $Label = if ([string]::IsNullOrWhiteSpace($DisplayLabel)) { $Record.Label } else { $DisplayLabel }
    $Value = if ($Record -and -not [string]::IsNullOrWhiteSpace([string]$Record.Value)) {
        [string]$Record.Value
    }
    else {
        "Evidence not captured."
    }

    if ($Value -eq "Not captured in this report.") {
        $Value = "Evidence not captured."
    }

    $ValueClass = if ($Value -eq "Evidence not captured.") {
        "system-evidence-value system-evidence-value-missing"
    }
    else {
        "system-evidence-value"
    }

    $SafeLabel = ConvertTo-HtmlSafeText (($Label -replace ':$', '').Trim())
    $SafeValue = ConvertTo-HtmlSafeText $Value

    return @"
                    <div class="system-evidence-row system-evidence-row-informational">
                        <span class="system-evidence-label">$SafeLabel</span>
                        <span class="$ValueClass">$SafeValue</span>
                    </div>
"@
}

# Wraps a System body block in a native collapsible card.
# This keeps the System section segmented without adding JavaScript or
# changing the underlying evidence/check logic.
# v0.43: Moved from the main renderer after confirming it only
# depends on explicit parameters and ConvertTo-HtmlSafeText.
function New-ArcForgeSystemCollapsibleCardHtml {
    param (
        [string]$Id = "",
        [string]$Title,
        [string]$Description,
        [string]$BodyHtml,
        [string]$ExtraClass = "",
        [bool]$OpenByDefault = $false
    )

    $SafeTitle = ConvertTo-HtmlSafeText $Title
    $SafeDescription = ConvertTo-HtmlSafeText $Description
    $CardClass = "system-collapsible-card"
    $IdAttribute = ""
    $OpenAttribute = ""

    if (-not [string]::IsNullOrWhiteSpace($ExtraClass)) {
        $CardClass = "$CardClass $ExtraClass"
    }

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $SafeId = ConvertTo-HtmlSafeText $Id
        $IdAttribute = " id=`"$SafeId`""
    }

    if ($OpenByDefault) {
        $OpenAttribute = " open"
    }

    return @"
        <details$IdAttribute class="$CardClass"$OpenAttribute>
            <summary class="system-collapsible-summary">
                <span class="system-collapsible-title">$SafeTitle</span>
                <span class="system-collapsible-chevron" aria-hidden="true">›</span>
            </summary>
            <div class="system-collapsible-card-body">
                <p class="system-collapsible-description">$SafeDescription</p>
$BodyHtml
            </div>
        </details>
"@
}

# Builds a detail anchor section from existing report lines only.
# These sections are intentionally simple and static: the snapshot cards link here
# when a tech wants more evidence without requiring JavaScript.
#
# v0.50: Moved from New-ArcForgeSystemEvidenceHtml after confirming it only
# depends on explicit parameters, Get-ArcForgeFlattenedLines,
# ConvertTo-ArcForgeSystemEvidenceRecord, New-ArcForgeSystemEvidenceRowHtml,
# New-ArcForgeSystemCollapsibleCardHtml, static HTML assembly, and basic string
# handling.
# Module owner: scripts/ArcForge.HtmlReport.ps1
function New-ArcForgeSystemDetailSectionHtml {
    param (
        [string]$Id,
        [string]$Title,
        [string]$Description,
        [object[]]$Lines
    )

    $DetailRows = @()

    foreach ($Line in (Get-ArcForgeFlattenedLines -Lines $Lines)) {
        $Record = ConvertTo-ArcForgeSystemEvidenceRecord -Line $Line
        if ($null -ne $Record) {
            $DetailRows += New-ArcForgeSystemEvidenceRowHtml -Record $Record
        }
    }

    if (-not $DetailRows -or $DetailRows.Count -eq 0) {
        $DetailRows += @"
                    <div class="system-detail-empty muted">No detail lines captured for this subsection.</div>
"@
    }

    $DetailRowsHtml = $DetailRows -join "`n"

    $DetailBodyHtml = @"
                        <div class="system-evidence-rows">
$DetailRowsHtml
                        </div>
"@

    return New-ArcForgeSystemCollapsibleCardHtml -Id $Id -Title $Title -Description $Description -BodyHtml $DetailBodyHtml -ExtraClass "system-detail-collapsible-card"
}

# Builds a System snapshot panel from already-prepared row HTML.
# Optional anchor-style footer links let the snapshot stay compact while still
# giving technicians a clear path to deeper static evidence sections later in
# the same HTML report.
#
# v0.44: Moved from the main renderer after confirming it only depends on
# explicit parameters and ConvertTo-HtmlSafeText.
function New-ArcForgeSystemPanelHtml {
    param (
        [string]$Title,
        [string]$Description,
        [string]$RowsHtml,
        [string]$ExtraClass = "",
        [string]$LinkHref = "",
        [string]$LinkText = ""
    )

    $SafeTitle = ConvertTo-HtmlSafeText $Title
    $SafeDescription = ConvertTo-HtmlSafeText $Description
    $PanelClass = "system-evidence-panel"

    if (-not [string]::IsNullOrWhiteSpace($ExtraClass)) {
        $PanelClass = "$PanelClass $ExtraClass"
    }

    $LinkHtml = ""
    if (-not [string]::IsNullOrWhiteSpace($LinkHref) -and -not [string]::IsNullOrWhiteSpace($LinkText)) {
        $SafeLinkHref = ConvertTo-HtmlSafeText $LinkHref
        $SafeLinkText = ConvertTo-HtmlSafeText $LinkText
        $LinkHtml = @"
                    <div class="system-panel-footer">
                        <a class="system-panel-link" href="$SafeLinkHref"><span class="system-panel-link-text">$SafeLinkText</span></a>
                    </div>
"@
    }

    return @"
                <article class="$PanelClass">
                    <div class="system-panel-header">
                        <h3>$SafeTitle</h3>
                        <p>$SafeDescription</p>
                    </div>
                    <div class="system-evidence-rows">
$RowsHtml
                    </div>
$LinkHtml
                </article>
"@
}

# Builds the System snapshot panel group from caller-prepared panel
# definitions. The caller still owns evidence selection, row/body preparation,
# panel ordering, section orchestration, and final System layout.
#
# v0.52: Moved the narrow repeated snapshot panel assembly loop from the main
# renderer after confirming it only depends on explicit panel definition fields
# and New-ArcForgeSystemPanelHtml.
function New-ArcForgeSystemPanelGroupHtml {
    param (
        [object[]]$Panels
    )

    $PanelHtml = @(
        foreach ($Panel in $Panels) {
            if ($null -eq $Panel) {
                continue
            }

            New-ArcForgeSystemPanelHtml `
                -Title $Panel.Title `
                -Description $Panel.Description `
                -RowsHtml $Panel.RowsHtml `
                -ExtraClass $Panel.ExtraClass `
                -LinkHref $Panel.LinkHref `
                -LinkText $Panel.LinkText
        }
    )

    return ($PanelHtml -join "`n")
}

# Builds the default-open System Overview card from already-prepared snapshot
# panel HTML. This is presentation assembly only: callers still own evidence
# collection, record selection, panel ordering, section orchestration, and final
# report template placement.
#
# v0.51: Moved from the main renderer after confirming it only depends on one
# explicit panel HTML string and New-ArcForgeSystemCollapsibleCardHtml.
function New-ArcForgeSystemOverviewHtml {
    param (
        [string]$PanelsHtml
    )

    $SystemOverviewBodyHtml = @"
                        <div class="system-evidence-grid">
$PanelsHtml
                        </div>
"@

    return New-ArcForgeSystemCollapsibleCardHtml -Title "System Overview" -Description "Snapshot cards for endpoint platform, vital signs, storage, process health, and core service evidence." -BodyHtml $SystemOverviewBodyHtml -ExtraClass "system-overview-card" -OpenByDefault $true
}

# -----------------------------------------------------------------------------
# Report Navigation Helpers
# -----------------------------------------------------------------------------
# v0.42 extracted slice: Report Navigation helpers.
# These helpers build static anchor navigation only. Every href target must
# match an id in the final HTML template. No JavaScript is used.

# Builds the three compact status segments shown beside readiness-domain
# links in the HTML report sidebar.
#
# Why this exists:
# - v0.19 is still a presentation-layer release.
# - The sidebar segments give the report a quick dashboard-style glance
#   without adding JavaScript, external dependencies, or a new GUI layer.
# - This helper only converts an existing readiness status into small HTML
#   spans. It does not inspect the computer or rerun any health checks.
#
# Input:
# - A readiness status from Get-ArcForgeSectionReadiness:
#   Critical, Attention, OK, or No Data.
#
# Output:
# - A string containing three small <span> elements.
#
# Important:
# - This is presentation-only.
# - This does not change check logic, scoring, console output, or TXT output.
# - The sidebar status should always match the Readiness Overview card that
#   was built from the same readiness object.
function New-ArcForgeSidebarStatusSegmentsHtml {
    param (
        [string]$Status
    )

    $SegmentClass = "sidebar-segment-empty"
    $FilledSegments = 0

    switch ($Status) {
        "Critical" {
            $SegmentClass = "sidebar-segment-critical"
            $FilledSegments = 1
        }
        "Attention" {
            $SegmentClass = "sidebar-segment-attention"
            $FilledSegments = 2
        }
        "OK" {
            $SegmentClass = "sidebar-segment-ok"
            $FilledSegments = 3
        }
        default {
            $SegmentClass = "sidebar-segment-empty"
            $FilledSegments = 0
        }
    }

    $Segments = @()

    for ($Index = 1; $Index -le 3; $Index++) {
        if ($Index -le $FilledSegments) {
            $Segments += "<span class=""sidebar-segment $SegmentClass""></span>"
        }
        else {
            $Segments += "<span class=""sidebar-segment sidebar-segment-empty""></span>"
        }
    }

    return ($Segments -join "")
}

# Builds the static sidebar navigation used by the HTML report.
#
# Why this exists:
# - v0.18 added quick-jump navigation for the major report sections.
# - v0.19 reuses the existing Readiness Overview data to add small status
#   segments beside the five primary readiness domains only.
# - This helper keeps the navigation markup in one small place instead of
#   scattering repeated <a> tags throughout the main HTML template.
#
# Input:
# - ReadinessCards are the same objects used by New-ArcForgeReadinessOverviewHtml.
# - The cards are calculated once, then reused by both the Readiness Overview
#   and this sidebar navigation. That keeps both views in sync.
#
# Important:
# - These are normal internal anchor links like href="#network".
# - The status segments are visual/presentation-only.
# - No JavaScript is used.
# - No external dependencies are used.
# - This does not change any check logic, console output, or TXT output.
#
# Troubleshooting rule:
# - Every href="#section-name" in this helper must match an id="section-name"
#   somewhere in the HTML template below.
# - Sidebar status segments should only appear for System, Network,
#   Software Readiness, Security, and Updates.
# - If a segment does not match the Readiness Overview card, inspect the
#   readiness card Name values first.
#
# Output:
# - A string containing the complete sidebar <aside> block.
function New-ArcForgeReportNavigationHtml {
    param (
        [object[]]$ReadinessCards
    )

    $ReadinessByName = @{}

    foreach ($Card in $ReadinessCards) {
        $ReadinessByName[$Card.Name] = $Card
    }

    $NavigationItems = @(
        [pscustomobject]@{ Label = "Report Summary";       Anchor = "report-summary";       ShowStatus = $false }
        [pscustomobject]@{ Label = "Incident Summary";     Anchor = "incident-summary";     ShowStatus = $false }
        [pscustomobject]@{ Label = "Readiness Overview";   Anchor = "readiness-overview";   ShowStatus = $false }
        [pscustomobject]@{ Label = "System";               Anchor = "system";               ShowStatus = $true  }
        [pscustomobject]@{ Label = "Network";              Anchor = "network";              ShowStatus = $true  }
        [pscustomobject]@{ Label = "Software Readiness";   Anchor = "software-readiness";   ShowStatus = $true  }
        [pscustomobject]@{ Label = "Security";             Anchor = "security";             ShowStatus = $true  }
        [pscustomobject]@{ Label = "Updates";              Anchor = "updates";              ShowStatus = $true  }
        [pscustomobject]@{ Label = "Recommended Actions";  Anchor = "recommended-actions";  ShowStatus = $false }
        [pscustomobject]@{ Label = "Raw Findings";         Anchor = "raw-findings";         ShowStatus = $false }
    )

    $NavigationLinks = @()

    foreach ($Item in $NavigationItems) {
        $SafeLabel = ConvertTo-HtmlSafeText $Item.Label
        $SafeAnchor = ConvertTo-HtmlSafeText $Item.Anchor

        # v0.24 Part 2:
        # System is the first sidebar section to use native, no-JavaScript
        # parent/child navigation. The parent row expands or collapses the
        # System tree, while the child links jump to the System snapshot and
        # detail anchors.
        #
        # Important:
        # - This is HTML presentation only.
        # - It does not rerun checks.
        # - It does not change readiness scoring.
        # - It does not change console output or TXT report output.
        if ($Item.Label -eq "System" -and $Item.ShowStatus -and $ReadinessByName.ContainsKey($Item.Label)) {
            $Card = $ReadinessByName[$Item.Label]
            $SafeStatus = ConvertTo-HtmlSafeText $Card.Status
            $SegmentsHtml = New-ArcForgeSidebarStatusSegmentsHtml -Status $Card.Status

            $NavigationLinks += @"
                <details class="sidebar-section-group" open>
                    <summary class="sidebar-section-summary" title="$SafeLabel readiness: $SafeStatus" aria-label="$SafeLabel readiness: $SafeStatus">
                        <span class="sidebar-section-summary-label">$SafeLabel</span>
                        <span class="sidebar-status-segments" aria-hidden="true">$SegmentsHtml</span>
                    </summary>
                    <a class="sidebar-section-subitem" href="#$SafeAnchor">System Overview</a>
                    <a class="sidebar-section-subitem" href="#system-endpoint-platform-details">Endpoint Platform Details</a>
                    <a class="sidebar-section-subitem" href="#system-vital-signs-details">Vital Signs Details</a>
                    <a class="sidebar-section-subitem" href="#system-storage-details">Storage Details</a>
                    <a class="sidebar-section-subitem" href="#system-process-details">Process Health Details</a>
                    <a class="sidebar-section-subitem" href="#system-core-services-details">Core Services Details</a>
                </details>
"@
            continue
        }

        if ($Item.ShowStatus -and $ReadinessByName.ContainsKey($Item.Label)) {
            $Card = $ReadinessByName[$Item.Label]
            $SafeStatus = ConvertTo-HtmlSafeText $Card.Status
            $SegmentsHtml = New-ArcForgeSidebarStatusSegmentsHtml -Status $Card.Status

            $NavigationLinks += @"
                <a class="sidebar-link sidebar-link-with-status" href="#$SafeAnchor" title="$SafeLabel readiness: $SafeStatus" aria-label="$SafeLabel readiness: $SafeStatus">
                    <span class="sidebar-link-label">$SafeLabel</span>
                    <span class="sidebar-status-segments" aria-hidden="true">$SegmentsHtml</span>
                </a>
"@
        }
        else {
            $NavigationLinks += "                <a class=""sidebar-link"" href=""#$SafeAnchor"">$SafeLabel</a>"
        }
    }

    $NavigationLinksHtml = $NavigationLinks -join "`n"

    return @"
        <aside class="report-sidebar">
            <div class="sidebar-title">Report Navigation</div>
            <div class="sidebar-subtitle">Jump to a major report section.</div>
            <nav class="sidebar-nav" aria-label="ArcForge report sections">
$NavigationLinksHtml
            </nav>
        </aside>
"@
}


