variable "repo_names" { type = list(string) }

resource "aws_ecr_repository" "main" {
  count                = length(var.repo_names)
  name                 = var.repo_names[count.index]
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "repo_urls" { value = aws_ecr_repository.main[*].repository_url }
