using Microsoft.EntityFrameworkCore;

namespace UsersAPI;

public sealed class UserAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string Role { get; set; } = "User";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public sealed class UsersDbContext(DbContextOptions<UsersDbContext> options) : DbContext(options)
{
    public DbSet<UserAccount> Users => Set<UserAccount>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<UserAccount>(builder =>
        {
            builder.HasKey(user => user.Id);
            builder.Property(user => user.Id).ValueGeneratedNever();
            builder.Property(user => user.Name).IsRequired().HasMaxLength(150);
            builder.Property(user => user.Email).IsRequired().HasMaxLength(150);
            builder.HasIndex(user => user.Email).IsUnique();
            builder.Property(user => user.PasswordHash).IsRequired();
            builder.Property(user => user.Role).IsRequired().HasMaxLength(30);
            builder.Property(user => user.CreatedAt).IsRequired();
        });
    }
}

public sealed record RegisterUserRequest(string Name, string Email, string Password);
public sealed record LoginRequest(string Email, string Password);
public sealed record AuthResponse(string Token, Guid UserId, string Name, string Email, string Role);
