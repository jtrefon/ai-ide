using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Vcs;

public interface IGitService
{
    Task<bool> IsRepoAsync(string repoRoot, CancellationToken ct = default);
    Task<string> StatusAsync(string repoRoot, bool porcelain = true, CancellationToken ct = default);
    Task<string> CurrentBranchAsync(string repoRoot, CancellationToken ct = default);
    Task<IReadOnlyList<string>> BranchListAsync(string repoRoot, CancellationToken ct = default);
    Task<bool> CheckoutAsync(string repoRoot, string branch, bool create = false, CancellationToken ct = default);
    Task<bool> CommitAllAsync(string repoRoot, string message, CancellationToken ct = default);
}
