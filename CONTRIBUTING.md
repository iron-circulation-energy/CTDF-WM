# Contributing

Please report reproducibility problems through GitHub issues, with the commit, MATLAB and toolbox versions, solver, entry point, expected behavior and relevant error output. Remove credentials and private paths from logs. State whether you used synthetic or prepared weather inputs and whether the design artifact is available.

For changes, create a branch and open a pull request against `main`. Explain the problem, the resulting behavior and the validation performed. Keep model/parameter changes separate from documentation and plotting changes so their scientific effects can be reviewed.

Run the existing test manifest using the command in the README. Report failures and missing prerequisites explicitly. A change to a scientific assumption, evaluation split, cost boundary or selection rule should identify which manuscript results need to be recomputed. Preserve data provenance and record how derived inputs were produced.

Do not commit downloaded weather, credentials, manuscript drafts or generated runs. Share large reproduction artifacts through an agreed archival location and record checksums. The selected design and its provenance are required release artifacts, even when distributed separately from Git.

Original code contributions use the repository's MIT license. Identify any third-party data or code and retain the applicable notices. Authorship of the paper is maintained by the research team and is distinct from repository commit history.
